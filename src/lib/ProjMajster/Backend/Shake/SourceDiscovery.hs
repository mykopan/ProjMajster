{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Backend.Shake.SourceDiscovery
  ( DiscoveredSource(..)
  , SourceManifest(..)
  , sourceManifests
  , sourceDiscoveryRules
  , discoverSources
  , parseSourceManifestContent
  , readSourceManifest
  ) where

import Data.List (sort)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Development.Shake
import Development.Shake.FilePath

import ProjMajster.Core
import ProjMajster.Graph

data DiscoveredSource = DiscoveredSource
  { discoveredSourceOwner :: TargetName
  , discoveredSourceBaseDir :: FilePath
  , discoveredSourcePath :: FilePath
  , discoveredSourceLanguage :: Language
  } deriving (Eq, Ord, Show)

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
    sources <- discoverSources (sourceManifestDiscovery manifest)
    writeSourceManifest output sources

discoverSources :: SourceDiscovery -> Action [DiscoveredSource]
discoverSources discovery = do
  files <- sort <$> getDirectoryFiles
    (sourceGlobBaseDir glob)
    [sourceGlobPattern glob]
  pure
    [ DiscoveredSource
        { discoveredSourceOwner = sourceDiscoveryOwner discovery
        , discoveredSourceBaseDir = sourceGlobBaseDir glob
        , discoveredSourcePath = file
        , discoveredSourceLanguage = sourceGlobLanguage glob
        }
    | file <- files
    ]
  where
    glob = sourceDiscoveryGlob discovery

writeSourceManifest :: FilePath -> [DiscoveredSource] -> Action ()
writeSourceManifest output sources =
  writeFileChanged output $
    unlines (map encodeDiscoveredSource sources)

readSourceManifest :: SourceManifest -> Action [DiscoveredSource]
readSourceManifest manifest =
  parseSourceManifestContent <$> readFile' (sourceManifestPath manifest)

parseSourceManifestContent :: String -> [DiscoveredSource]
parseSourceManifestContent =
  mapMaybe parseDiscoveredSource . lines

encodeDiscoveredSource :: DiscoveredSource -> String
encodeDiscoveredSource source =
  Text.unpack $ Text.intercalate "\t"
    [ targetNameText (discoveredSourceOwner source)
    , displayLanguage (discoveredSourceLanguage source)
    , Text.pack (discoveredSourceBaseDir source)
    , Text.pack (discoveredSourcePath source)
    ]

parseDiscoveredSource :: String -> Maybe DiscoveredSource
parseDiscoveredSource line =
  case Text.splitOn "\t" (Text.pack line) of
    [owner, languageText, baseDir, path] -> do
      language <- parseLanguage languageText
      pure DiscoveredSource
        { discoveredSourceOwner = TargetName owner
        , discoveredSourceBaseDir = Text.unpack baseDir
        , discoveredSourcePath = Text.unpack path
        , discoveredSourceLanguage = language
        }
    _ -> Nothing

displayLanguage :: Language -> Text
displayLanguage C = "c"
displayLanguage Cxx = "cxx"
displayLanguage (CustomLanguage language) =
  "custom:" <> language

parseLanguage :: Text -> Maybe Language
parseLanguage "c" = Just C
parseLanguage "cxx" = Just Cxx
parseLanguage languageText =
  CustomLanguage <$> Text.stripPrefix "custom:" languageText

targetNameString :: TargetName -> String
targetNameString (TargetName name) =
  Text.unpack name
