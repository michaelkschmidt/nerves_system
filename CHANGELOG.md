# Changelog

## v0.1.5
  * Bug Fixes
    * URL encode for downloading S3 assets
    * Ability to use prerelease in nerves_system_*
    * Removed dependency on HTTPoison / hackney
    * Support for downloading through proxies

## v0.1.4
  * Bug Fixes
    * Resolve local cache dir when Env bootstrap called form loadpaths. Fixes subsequent calls to `mix firmware`

## v0.1.3
  * Enhancements
    * Added option to use local cache provider. See https://hexdocs.pm/nerves/systems.html#building-nerves-systems for more information.

## v0.1.2
  * Bug Fixes
    * Simplified providers dependencies to always include all.

## v0.1.1

  * Bug fixes
    * Fixed local compiler compressed output

  * Enhancements
    * Added mix compress.nerves_system
