/// Shared RAM-planning arithmetic for a Studio. This does not sample hardware
/// or estimate the memory requirements of any particular model or shard.
public enum HostRAMBudget {
    /// Keep at least16GiB or20% of physical RAM for the native runtime.
    /// Round fractional bytes upward, matching the existing admission policy.
    public static func nativeHeadroom(physicalBytes: UInt64) -> UInt64 {
        let fifth = physicalBytes / 5 + (physicalBytes % 5 == 0 ? 0 : 1)
        return max(UInt64(16) << 30, fifth)
    }
}
