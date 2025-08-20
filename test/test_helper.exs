# Ensure the Predicator application is started before tests run
# This ensures system functions are registered and available
Application.ensure_all_started(:predicator)

ExUnit.start()
