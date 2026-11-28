PYTHON ?= python3
SPECIFY ?= .venv/bin/specify
export NODE ?= fios-core
PREVIEW_AGENT := local.fios.preview-telemetry

.PHONY: check test enrollment-test enrollment-acceptance scheduling-test scheduling-acceptance chat-test chat-acceptance pair-test pair-acceptance moe-test moe-acceptance spec-tools spec-check sample agent dashboard dashboard-stop
check: spec-check test
	docker compose config --quiet

test:
	PYTHONPATH=src $(PYTHON) -B -m unittest discover -s tests -v

enrollment-test:
	PYTHONPATH=src $(PYTHON) -B -m unittest discover -s tests -p 'test_*enrollment*.py' -v

enrollment-acceptance:
	PYTHONPATH=src:tests $(PYTHON) -B tests/macos/verify_enrollment.py

scheduling-test:
	PYTHONPATH=src $(PYTHON) -B -m unittest discover -s tests -p 'test_job*.py' -v

scheduling-acceptance:
	PYTHONPATH=src:tests $(PYTHON) -B tests/macos/verify_scheduling.py

chat-test:
	PYTHONPATH=src $(PYTHON) -B -m unittest discover -s tests -p "test_chat*.py" -v
	PYTHONPATH=src $(PYTHON) -B -m unittest discover -s tests -p "test_mini_inference.py" -v
	PYTHONPATH=src $(PYTHON) -B -m unittest discover -s tests -p "test_model_catalog.py" -v

chat-acceptance:
	PYTHONPATH=src:tests $(PYTHON) -B tests/macos/verify_chat.py

pair-test:
	PYTHONPATH=src:tests $(PYTHON) -B -m unittest test_pair_trials test_jaccl_transport test_chat_studio -v

moe-test:
	PYTHONPATH=src:tests $(PYTHON) -B -m unittest test_large_moe -v

moe-acceptance: pair-acceptance chat-acceptance
	$(PYTHON) -B tests/macos/verify_moe_webkit.py

pair-acceptance:
	PYTHONPATH=src:tests $(PYTHON) -B tests/macos/verify_pair.py

spec-tools:
	$(PYTHON) -m venv .venv
	.venv/bin/python -m pip --isolated install --index-url https://pypi.org/simple --only-binary=:all: --require-hashes -r .specify/requirements-macos-arm64-py315.txt
	.venv/bin/python -m pip check
	@if [ ! -f .specify/feature.json ]; then \
		SPECIFY_FEATURE_DIRECTORY=specs/001-platform-foundation bash .specify/scripts/bash/check-prerequisites.sh --require-spec --require-tasks; \
	fi

spec-check:
	$(SPECIFY) integration status
	SPECIFY_FEATURE_NO_PERSIST=1 bash .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks

sample:
	PYTHONPATH=src $(PYTHON) -B -m backend.host_agent --node fios-core

agent:
	PYTHONPATH=src $(PYTHON) -B -m backend.host_agent --node "$$NODE" --watch

dashboard: sample
	docker --context orbstack compose up --build --detach --wait --wait-timeout 60
	@if ! launchctl list "$(PREVIEW_AGENT)" >/dev/null 2>&1; then \
		launchctl submit -l "$(PREVIEW_AGENT)" -e "$(CURDIR)/.fios/telemetry.log" -- \
			/usr/bin/env "PYTHONPATH=$(CURDIR)/src" "$(shell command -v $(PYTHON))" -B \
			-m backend.host_agent --node fios-core --watch --directory "$(CURDIR)/.fios/observations"; \
	fi

dashboard-stop:
	docker --context orbstack compose down
	@if launchctl list "$(PREVIEW_AGENT)" >/dev/null 2>&1; then launchctl remove "$(PREVIEW_AGENT)"; fi
