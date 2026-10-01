/// How many git processes Spoon runs at once for independent reads, such
/// as verifying several tags. Enough to overlap their startup and I/O
/// without crowding out the commands the user starts.
public let concurrentGitReads: UInt = 4
