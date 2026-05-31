module ProjMajster.Core.Transform
  ( TransformName(..)
  , TransformKind(..)
  , TransformRule(..)
  , InputSelector(..)
  , OutputFileMapping(..)
  , OutputMapping(..)
  , TransformAction(..)
  , BuiltinTransform(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.FileRole (FileRole)
import ProjMajster.Core.SourceSet (Language)

newtype TransformName = TransformName
  { transformNameText :: Text
  } deriving (Eq, Ord, Show, Read)

data TransformKind
  = MapTransform
  | FoldTransform
  deriving (Eq, Ord, Show, Read)

data TransformRule = TransformRule
  { transformName :: TransformName
  , transformKind :: TransformKind
  , transformInput :: InputSelector
  , transformOutput :: OutputMapping
  , transformAction :: TransformAction
  } deriving (Eq, Ord, Show, Read)

data InputSelector
  = InputLanguage Language
  | InputRole FileRole
  | InputAnyObject
  | InputLinkInput
  | InputAny
  deriving (Eq, Ord, Show, Read)

data OutputMapping
  = OutputObject
  | OutputGeneratedSource Language FilePath
  | OutputFiles [OutputFileMapping]
  deriving (Eq, Ord, Show, Read)

data OutputFileMapping = OutputFileMapping
  { outputFileRole :: FileRole
  , outputFilePath :: FilePath
  } deriving (Eq, Ord, Show, Read)

data TransformAction
  = BuiltinAction BuiltinTransform
  | CustomAction Text
  deriving (Eq, Ord, Show, Read)

data BuiltinTransform
  = BuiltinCompileC
  | BuiltinCompileCxx
  | BuiltinLink
  deriving (Eq, Ord, Show, Read)
