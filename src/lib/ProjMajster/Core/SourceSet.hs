{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.SourceSet
  ( Language(..)
  , SourcePattern(..)
  , SourceSet(..)
  ) where

import Data.Text (Text)

data Language
  = C
  | Cxx
  | CustomLanguage Text
  deriving (Eq, Ord, Show, Read)

data SourcePattern = SourcePattern
  { sourcePatternLanguage :: Language
  , sourcePatternBaseDir :: FilePath
  , sourcePatternGlob :: FilePath
  } deriving (Eq, Ord, Show, Read)

data SourceSet = SourceSet
  { sourceSetName :: Text
  , sourceSetPatterns :: [SourcePattern]
  } deriving (Eq, Show, Read)
