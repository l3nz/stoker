

## Testing


	mix test


## Testing of cluster

Make sure epmd is up, and all other tests pass.

	 mix test --only with_epmd


## Misc checks

	mix format
	mix credo
	mix dialyzer

## Publishing

Check version in mix.exs 

	mix hex.publish

