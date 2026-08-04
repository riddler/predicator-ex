# Ensure the Predicator application is started before tests run
# This ensures system functions are registered and available
Application.ensure_all_started(:predicator)

# Predicates written with `=` emit a deprecation warning (px-8um.5), and the
# suite is full of them. Capture log output so the runner stays readable;
# tests that assert on the warning use ExUnit.CaptureLog explicitly.
ExUnit.start(capture_log: true)
