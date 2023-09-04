# start the current node as a manager
:ok = LocalCluster.start()

# start your application tree manually
Application.ensure_all_started(:stoker)

# Exclude all external tests from running
ExUnit.configure(exclude: [with_epmd: true])
# run all tests!
ExUnit.start()
