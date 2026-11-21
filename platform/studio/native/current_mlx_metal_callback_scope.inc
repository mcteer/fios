template <class Work, class Cleanup>
void fios_owned_metal_callback(const std::shared_ptr<FiosMetalCapture>& capture,
                               Error& error, Work&& work, Cleanup&& cleanup) {
  auto record = [&](const char* message) {
    if (!error.valid()) error.set_message(std::make_shared<std::string>(message));
  };
  try {
    FiosRequestOwnerScope scope(fios_take_metal_request_owners(capture));
    try { work(); }
    catch (const std::exception& failure) { record(failure.what()); }
    catch (...) { record("Native Metal callback failed"); }
    if (error.valid()) scope.fence();
    try { cleanup(); }
    catch (...) { scope.fence(); throw; }
  } catch (const std::exception& failure) {
    record(failure.what());fios_metal_capture_end(capture, true);
  } catch (...) {
    record("Native Metal owner context unavailable");fios_metal_capture_end(capture, true);
  }
}
