module ProjMajster.Backend.Shake
  ( DiscoveredSource(..)
  , SourceManifest(..)
  , TransformInstance(..)
  , sourceManifests
  , sourceDiscoveryRules
  , discoverSources
  , parseSourceManifestContent
  , planMapTransforms
  , planTargetTransforms
  , readSourceManifest
  , transformInstanceRules
  ) where

import ProjMajster.Backend.Shake.SourceDiscovery
import ProjMajster.Backend.Shake.Transform
