{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.DSL.SourceSet
  ( SourceSetM
  , c
  , cxx
  , customSource
  ) where

import Control.Monad.State.Strict (modify)
import Data.Text (Text)
import qualified Data.Text as Text

import ProjMajster.Core
import ProjMajster.DSL.Internal

c :: FilePath -> SourceSetM ()
c = sourcePattern C

cxx :: FilePath -> SourceSetM ()
cxx = sourcePattern Cxx

customSource :: Text -> FilePath -> SourceSetM ()
customSource language =
  sourcePattern (CustomLanguage language)

sourcePattern :: Language -> FilePath -> SourceSetM ()
sourcePattern language glob = SourceSetM $
  modify $ \draft -> draft
    { sourceSetDraftPatterns =
        sourceSetDraftPatterns draft ++
        [ SourcePattern
            { sourcePatternLanguage = language
            , sourcePatternBaseDir = sourceSetDraftBaseDir draft
            , sourcePatternGlob = glob
            }
        ]
    , sourceSetDraftName =
        if null (sourceSetDraftName draft)
          then Text.unpack (languageName language)
          else sourceSetDraftName draft
    }

languageName :: Language -> Text
languageName C = "c"
languageName Cxx = "cxx"
languageName (CustomLanguage name) = name
