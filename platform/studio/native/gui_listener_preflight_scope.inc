    private func launch(args: [String], options: ServerOptions) {
        // A listener belongs to its launcher, not to another process with the
        // same executable name. Refuse before changing defaults or spawning.
        guard pidsListening(on: options.port).isEmpty else {
            lastError = "Port \(options.port) is already in use. Stop its server through its owner before starting another."
            status = .error(lastError)
            return
        }
        do { try GenerationDefaultsFile.migrate(options) }
        catch {
            lastError = "Could not save generation defaults: \(error.localizedDescription)"
            status = .error(lastError)
            return
        }
        port = options.port
        api.host = options.host
        status = .starting
        lastError = ""
        clearServerLog()

    }
