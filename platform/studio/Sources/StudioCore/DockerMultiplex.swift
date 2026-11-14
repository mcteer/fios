import Foundation

enum DockerStreamError:Error { case invalid,overflow,closed }

// Docker's non-TTY stdcopy stream is not application framing. Decode this
// layer before interpreting the sandbox's own bounded version1 frames.
struct DockerMultiplex {
    private var buffer=Data()
    private var failed=false
    private var total=0
    mutating func append(_ bytes:Data) throws -> [Data] {
        guard !failed else { throw DockerStreamError.closed }
        do {
            guard bytes.count<=65536,buffer.count+bytes.count<=1<<20 else { throw DockerStreamError.overflow }
            buffer.append(bytes)
            var output:[Data]=[]
            while buffer.count>=8 {
                guard buffer[0]==1,buffer[1]==0,buffer[2]==0,buffer[3]==0 else { throw DockerStreamError.invalid }
                let length=buffer[4..<8].reduce(0) {($0<<8)|Int($1)}
                guard length>0,length<=65536,total<=(32<<20)-length else { throw DockerStreamError.overflow }
                guard buffer.count>=length+8 else { break }
                output.append(Data(buffer[8..<length+8]))
                total+=length;buffer=Data(buffer.dropFirst(length+8))
            }
            return output
        } catch { failed=true;buffer.removeAll();throw error }
    }
    mutating func finish() throws {
        guard !failed,buffer.isEmpty else { failed=true;buffer.removeAll();throw DockerStreamError.invalid }
        failed=true
    }
}
