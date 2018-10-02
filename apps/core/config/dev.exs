use Mix.Config

# Configuration for test environment

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
# Configure your database

config :core, Core.Patients, pk_hash_salt: "aNg9JXF48uQrIjFYSGXDmKEYBXuu0BOEbkecHq7uV9qmzOT1dvxoueZlsA022ahc3GgFfFHd"

config :core, :mongo, url: "mongodb://localhost:27017/medical_data"
config :core, :mongo_audit_log, url: "mongodb://localhost:27017/medical_data"
