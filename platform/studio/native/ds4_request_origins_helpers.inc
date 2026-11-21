// Additive fixture entries: real private Metal objects, no production globals,
// model, fabricated SDK object or rewritten producer body.
extern void *fios_native_request_owners_capture(void);
extern uint64_t fios_native_request_owners_enter(void *);
extern int fios_native_request_owners_leave(uint64_t);
extern void fios_native_request_owners_release(void *);
extern void *fios_native_request_owners_merge(void *,void *);
extern int fios_native_request_owners_covers_current(void *);
extern void fios_native_request_owners_uncertain(void);
int fios_ds4_fixture_enroll(void) {
#ifdef DS4_GPU_REQUEST_OWNER_HOOKS
    const ds4_gpu_request_owner_hooks hooks={fios_native_request_owners_capture,
        fios_native_request_owners_enter,fios_native_request_owners_leave,
        fios_native_request_owners_release,fios_native_request_owners_merge,
        fios_native_request_owners_covers_current,fios_native_request_owners_uncertain};
    return ds4_gpu_register_request_owner_hooks(&hooks);
#else
    return 0; // Prior source has no bridge; still run its real Metal work.
#endif
}
@interface FiosDS4OriginFixture:NSObject
@property(strong) id<MTLDevice> device;
@property(strong) id<MTLCommandQueue> queue;
@property(strong) id<MTLCommandBuffer> buffer;
@property(strong) id<MTLBuffer> data;
@property(strong) id<MTLSharedEvent> event;
@property pthread_t timer;
@property BOOL started;
@property BOOL joined;
@property BOOL gated;
@end
@implementation FiosDS4OriginFixture
@end
static void *fios_ds4_fixture_timer(void *raw) {
    @autoreleasepool {
        FiosDS4OriginFixture *fixture=(__bridge FiosDS4OriginFixture *)raw;
        struct timespec interval={3,0},remaining={0,0};
        while (nanosleep(&interval,&remaining)!=0 && errno==EINTR) interval=remaining;
        fixture.event.signaledValue=1;
    }
    return NULL;
}
void *fios_ds4_fixture_create(void) {
    @autoreleasepool {
        FiosDS4OriginFixture *fixture=[FiosDS4OriginFixture new];
        fixture.device=MTLCreateSystemDefaultDevice();
        fixture.queue=[fixture.device newCommandQueue];
        fixture.buffer=[fixture.queue commandBuffer];
        fixture.event=[fixture.device newSharedEvent];
        fixture.data=[fixture.device newBufferWithLength:64 options:MTLResourceStorageModeShared];
        if (!fixture.device || !fixture.queue || !fixture.buffer || !fixture.event || !fixture.data) return NULL;
#ifdef DS4_GPU_REQUEST_OWNER_HOOKS
        if (!fios_ds4_request_attach(fixture.buffer)) return NULL;
#endif
        return (__bridge_retained void *)fixture;
    }
}
int fios_ds4_fixture_encode(void *raw,unsigned half) {
    @autoreleasepool {
        FiosDS4OriginFixture *fixture=(__bridge FiosDS4OriginFixture *)raw;
        if (!fixture || half>1 || fixture.started) return 0;
#ifdef DS4_GPU_REQUEST_OWNER_HOOKS
        if (!fios_ds4_request_prepare(fixture.buffer)) return 0;
#endif
        if (!fixture.gated) {
            [fixture.buffer encodeWaitForEvent:fixture.event value:1];
            fixture.gated=YES;
        }
        id<MTLBlitCommandEncoder> encoder=[fixture.buffer blitCommandEncoder];
        if (!encoder) return 0;
        [encoder fillBuffer:fixture.data range:NSMakeRange(half*32,32) value:(uint8_t)(half+1)];
        [encoder endEncoding];
        return 1;
    }
}
int fios_ds4_fixture_submit(void *raw) {
    @autoreleasepool {
        FiosDS4OriginFixture *fixture=(__bridge FiosDS4OriginFixture *)raw;
        if (!fixture || fixture.started || !fixture.gated) return 0;
        pthread_t timer;
        if (pthread_create(&timer,NULL,fios_ds4_fixture_timer,raw)!=0) return 0;
        fixture.timer=timer;fixture.started=YES;
#ifdef DS4_GPU_REQUEST_OWNER_HOOKS
        return fios_ds4_request_commit(fixture.buffer);
#else
        [fixture.buffer commit];return 1;
#endif
    }
}
int fios_ds4_fixture_pending(void *raw) {
    FiosDS4OriginFixture *fixture=(__bridge FiosDS4OriginFixture *)raw;
    return fixture && fixture.buffer.status>=MTLCommandBufferStatusCommitted &&
        fixture.buffer.status<MTLCommandBufferStatusCompleted;
}
int fios_ds4_fixture_finish(void *raw) {
    @autoreleasepool {
        FiosDS4OriginFixture *fixture=(__bridge FiosDS4OriginFixture *)raw;
        if (!fixture) return 0;
        if (fixture.started && !fixture.joined) {
            if (pthread_join(fixture.timer,NULL)!=0) return 0;
            fixture.joined=YES;
        }
        if (fixture.buffer.status==MTLCommandBufferStatusNotEnqueued) return !fixture.gated;
        [fixture.buffer waitUntilCompleted];
        if (fixture.buffer.status!=MTLCommandBufferStatusCompleted) return 0;
        const uint8_t *bytes=fixture.data.contents;
        for (unsigned i=0;i<64;i++) if (bytes[i]!=(i<32?1:2)) return 0;
        return 1;
    }
}
void fios_ds4_fixture_release(void *raw) {
    @autoreleasepool {
        FiosDS4OriginFixture *fixture=(__bridge FiosDS4OriginFixture *)raw;
        if (!fixture || (fixture.started && !fixture.joined)) return;
        (void)CFBridgingRelease(raw);
    }
}
