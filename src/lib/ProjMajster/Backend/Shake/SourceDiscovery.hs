module ProjMajster.Backend.Shake.SourceDiscovery
  ( SourceManifest(..)
  , sourceManifests
  , sourceDiscoveryRules
  ) where

import Data.List (sort)
import qualified Data.Text as Text
import Development.Shake
import Development.Shake.FilePath

import ProjMajster.Core
import ProjMajster.Graph

data SourceManifest = SourceManifest
  { sourceManifestDiscovery :: SourceDiscovery
  , sourceManifestPath :: FilePath
  } deriving (Eq, Show)

sourceManifests :: BuildContext -> BuildGraph -> [SourceManifest]
sourceManifests context graph =
  zipWith (sourceManifest context) [0 :: Int ..] (graphSources graph)

sourceDiscoveryRules :: BuildContext -> BuildGraph -> Rules ()
sourceDiscoveryRules context graph =
  mapM_ sourceManifestRule manifests
  where
    manifests = sourceManifests context graph

sourceManifest :: BuildContext -> Int -> SourceDiscovery -> SourceManifest
sourceManifest context index discovery = SourceManifest
  { sourceManifestDiscovery = discovery
  , sourceManifestPath =
      buildInterDir (contextBuildDirs context)
        </> "sources"
        </> targetNameString (sourceDiscoveryOwner discovery)
        </> show index <.> "sources"
  }

sourceManifestRule :: SourceManifest -> Rules ()
sourceManifestRule manifest =
  sourceManifestPath manifest %> \output -> do
    let glob = sourceDiscoveryGlob (sourceManifestDiscovery manifest)
    files <- sort <$> getDirectoryFiles
      (sourceGlobBaseDir glob)
      [sourceGlobPattern glob]
    writeFileChanged output (unlines files)

targetNameString :: TargetName -> String
targetNameString (TargetName name) =
  Text.unpack name
