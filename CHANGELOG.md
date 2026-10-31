# Changelog

## x

* Documentation
* Builds cleanly on Elixir 1.20.5 / Erlang/OTP 29 (`.tool-versions` added for asdf)
* Updated dev dependencies (credo 1.7.19, dialyxir 1.4.8, ex_doc 0.40.4); old credo did not compile on OTP 29
* Replaced deprecated `Logger.warn/1` with `Logger.warning/2`; removed unused `require Logger`
* Fixed outdated tests (`:now_leader` event, removed `Stoker.hello/0` test)
* README: how to run the cluster tests (`mix test --include with_epmd`)
* Dialyzer passes with no warnings on Elixir 1.20.5 / OTP 29
* `mix docs` builds HTML only, no epub/markdown (#1); fixed callback reference in `Stoker.Activator.trigger/1` docs

## 0.1.3 (2023-09-07)

* Misc clean-up, documentation!


## 0.1.2 (2023-09-04)

* Initial release
* To be tested in integration
* Added Start_link to allow starting from Application

