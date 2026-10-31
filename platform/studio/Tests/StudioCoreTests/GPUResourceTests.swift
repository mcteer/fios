import Foundation

func runGPUResourceTests() throws {
    guard GPUResources.decode([:])==nil,GPUResources.decode(["Device Utilization %":true])==nil,
          GPUResources.decode(["Device Utilization %":101])==nil,GPUResources.decode(["Device Utilization %":Double.nan])==nil else {fatalError("GPU missing/invalid sensor fabricated utilization")}
    guard let zero=GPUResources.decode(["Device Utilization %":0]),zero.utilization==0,zero.inUseBytes==nil else {fatalError("Observed zero and missing memory conflated")}
    guard let measured=GPUResources.decode(["Device Utilization %":37.5,"In use system memory":1024,"Alloc system memory":2048]),measured.utilization==37.5,measured.inUseBytes==1024,measured.allocatedBytes==2048 else {fatalError("GPU counters incorrectly decoded")}
    guard GPUResources.decode(["Device Utilization %":0,"In use system memory":true])?.inUseBytes==nil,
          GPUResources.decode(["Device Utilization %":0,"Alloc system memory":UInt64.max])?.allocatedBytes==nil else {fatalError("GPU invalid or non-interoperable memory count accepted")}
    print("PASS: GPU registry counter bounds, genuine zero versus missing data and distinct in-use/allocated memory; no idle/capacity inference")
}
