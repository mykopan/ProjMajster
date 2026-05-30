{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.BuildStyle
  ( BuildStyle(..)
  , debug
  , release
  ) where

import Data.Text (Text)

newtype BuildStyle = BuildStyle
  { buildStyleName :: Text
  } deriving (Eq, Ord, Show)

debug :: BuildStyle
debug = BuildStyle "debug"

release :: BuildStyle
release = BuildStyle "release"
