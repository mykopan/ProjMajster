module ProjMajster.Backend.Shake
  ( DiscoveredSource(..)
  , SourceManifest(..)
  , sourceManifests
  , sourceDiscoveryRules
  , discoverSources
  , parseSourceManifestContent
  , readSourceManifest
  ) where

import ProjMajster.Backend.Shake.SourceDiscovery
