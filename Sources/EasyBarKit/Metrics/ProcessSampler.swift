import Darwin
import EasyBarShared
import Foundation

/// Samples lightweight process stats for EasyBar, Lua, and helper agents.
///
/// `ProcessSampler` is owned by `MetricsCoordinator`, which is an actor. That
/// actor already serializes access, so the sampler itself no longer needs a
/// separate lock around CPU baseline state.
final class ProcessSampler {
  /// Previous CPU sample used to compute utilization.
  private struct CPUSample {
    /// Sample timestamp.
    let sampledAt: TimeInterval
    /// Cumulative user plus system CPU time.
    let totalCPUTime: UInt64
  }

  /// Cached CPU samples keyed by process id.
  private var previousCPUSamples: [Int32: CPUSample] = [:]

  /// Samples the current EasyBar process.
  func sampleCurrentProcess(named name: String, now: Date) -> IPC.ProcessMetrics {
    return sampleProcess(named: name, pid: Int32(ProcessInfo.processInfo.processIdentifier), now: now)
  }

  /// Samples one arbitrary process identifier when it is available.
  func sampleProcess(named name: String, pid: Int32?, now: Date) -> IPC.ProcessMetrics {
    guard let pid, pid > 0 else {
      return IPC.ProcessMetrics(name: name, running: false)
    }

    guard let info = readTaskInfo(for: pid) else {
      previousCPUSamples.removeValue(forKey: pid)
      return IPC.ProcessMetrics(name: name, running: false, pid: pid)
    }

    let cpuPercent = resolveCPUPercent(pid: pid, totalCPUTime: info.totalCPUTime, now: now)

    return IPC.ProcessMetrics(
      name: name,
      running: true,
      pid: pid,
      cpuPercent: cpuPercent,
      residentSizeBytes: info.residentSizeBytes,
      threadCount: info.threadCount
    )
  }

  /// Samples the first running process matching one executable name.
  func sampleProcessNamed(
    named name: String,
    executableName: String,
    now: Date
  ) -> IPC.ProcessMetrics {
    let pid = firstPID(named: executableName)
    return sampleProcess(named: name, pid: pid, now: now)
  }

  /// Clears cached CPU deltas for one process when it fully goes away.
  func clear(pid: Int32?) {
    guard let pid else { return }
    previousCPUSamples.removeValue(forKey: pid)
  }

  /// Computes CPU percentage from the previous process sample.
  private func resolveCPUPercent(pid: Int32, totalCPUTime: UInt64, now: Date) -> Double? {
    let timestamp = now.timeIntervalSinceReferenceDate
    defer {
      previousCPUSamples[pid] = CPUSample(sampledAt: timestamp, totalCPUTime: totalCPUTime)
    }

    guard let previous = previousCPUSamples[pid] else {
      return nil
    }

    let wallDelta = timestamp - previous.sampledAt
    guard wallDelta > 0 else { return nil }

    let cpuDelta = totalCPUTime >= previous.totalCPUTime ? totalCPUTime - previous.totalCPUTime : 0
    let cpuSeconds = Double(cpuDelta) / 1_000_000_000
    return (cpuSeconds / wallDelta) * 100
  }

  /// Reads task memory, thread, and CPU counters for one process.
  private func readTaskInfo(for pid: Int32) -> (
    residentSizeBytes: UInt64, threadCount: Int, totalCPUTime: UInt64
  )? {
    var taskInfo = proc_taskinfo()
    let expectedSize = Int32(MemoryLayout<proc_taskinfo>.stride)

    let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, expectedSize)

    guard result == expectedSize else {
      return nil
    }

    let totalCPUTime = UInt64(taskInfo.pti_total_user) + UInt64(taskInfo.pti_total_system)
    return (
      residentSizeBytes: UInt64(taskInfo.pti_resident_size),
      threadCount: Int(taskInfo.pti_threadnum),
      totalCPUTime: totalCPUTime
    )
  }

  /// Returns the first process id with the given executable name.
  private func firstPID(named executableName: String) -> Int32? {
    let estimatedCount = Int(proc_listallpids(nil, 0))
    let capacity = max(estimatedCount + 32, 256)
    var pids = [Int32](repeating: 0, count: capacity)
    let bytes = Int32(pids.count * MemoryLayout<Int32>.stride)
    let filledBytes = proc_listallpids(&pids, bytes)

    guard filledBytes > 0 else { return nil }

    let filledCount = Int(filledBytes) / MemoryLayout<Int32>.stride

    for pid in pids.prefix(filledCount) where pid > 0 {
      var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
      let length = proc_name(pid, &buffer, UInt32(buffer.count))
      guard length > 0 else { continue }

      if String(cString: buffer) == executableName {
        return pid
      }
    }

    return nil
  }
}
