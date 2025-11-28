import Foundation
import Metal

/// SHA256 batch compute wrapper using a small constants buffer.
/// inputBuffer: device-private buffer with concatenated messages
/// outputBuffer: device-private buffer with 8 * batchSize uint32 words
class SHA256 {

    let device: MTLDevice

    let pipelineState: MTLComputePipelineState
    let inputBuffer: MTLBuffer
    let outputBuffer: MTLBuffer
    let constantsBuffer: MTLBuffer

    let threadgroupsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize

    let batchSize: Int

    /// keyLength: 33 = compressed, 65 = uncompressed
    init(on device: MTLDevice,
         batchSize: Int,
         inputBuffer: MTLBuffer,
         keyLength: UInt32) throws {

        self.device = device
        self.batchSize = batchSize
        self.inputBuffer = inputBuffer

        // Build compute pipeline
        self.pipelineState = try Helpers.buildPipelineState(
            kernelFunctionName: "sha256_batch_kernel"
        )

        // Output buffer: 8 uint32 words per message
        let outWordCountSha256 = batchSize * 8
        self.outputBuffer = device.makeBuffer(
            length: outWordCountSha256 * MemoryLayout<UInt32>.stride,
            options: .storageModePrivate
        )!

        // Constants buffer: SHA256Constants { uint numMessages; uint messageSize; }
        self.constantsBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * 2,
            options: .storageModeShared
        )!

        // Fill constants once
        let ptr = constantsBuffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        ptr[0] = UInt32(batchSize) // numMessages
        ptr[1] = keyLength         // messageSize (33 or 65)

        // Thread configuration
        (self.threadsPerThreadgroup, self.threadgroupsPerGrid) =
            try Helpers.getThreadConfig(
                pipelineState: pipelineState,
                batchSize: batchSize,
                threadsPerThreadgroupMultiplier: 16
            )
    }

    /// Encode SHA256 kernel for this batch into the given command buffer.
    func appendCommandEncoder(commandBuffer: MTLCommandBuffer) {
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(constantsBuffer, offset: 0, index: 2)
        encoder.dispatchThreadgroups(threadgroupsPerGrid,threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }

    func getOutputBuffer() -> MTLBuffer {
        return outputBuffer
    }

    // Debug helper
    public func printThreadConf() {
        print(
            String(
                format: "    SHA256:       │         %6d │       %6d │             %6d │",
                threadsPerThreadgroup.width,
                threadgroupsPerGrid.width,
                pipelineState.threadExecutionWidth
            )
        )
    }
}
