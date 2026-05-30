module ProjMajster.Core.Transform
  ( TransformName(..)
  , TransformKind(..)
  , TransformRule(..)
  , InputSelector(..)
  , OutputMapping(..)
  , TransformAction(..)
  , BuiltinTransform(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.FileRole (FileRole)
import ProjMajster.Core.SourceSet (Language)

newtype TransformName = TransformName
  { transformNameText :: Text
  } deriving (Eq, Ord, Show)

data TransformKind
  = MapTransform
  | FoldTransform
  deriving (Eq, Ord, Show)

data TransformRule = TransformRule
  { transformName :: TransformName
  , transformKind :: TransformKind
  , transformInput :: InputSelector
  , transformOutput :: OutputMapping
  , transformAction :: TransformAction
  } deriving (Eq, Ord, Show)

data InputSelector
  = InputLanguage Language
  | InputRole FileRole
  | InputAnyObject
  | InputLinkInput
  | InputAny
  deriving (Eq, Ord, Show)

data OutputMapping
  = OutputObject
  | OutputGeneratedSource Language FilePath
  | OutputTargetBinary
  | OutputCustom FileRole FilePath
  deriving (Eq, Ord, Show)

data TransformAction
  = BuiltinAction BuiltinTransform
  | CustomAction Text
  deriving (Eq, Ord, Show)

data BuiltinTransform
  = BuiltinCompileC
  | BuiltinCompileCxx
  | BuiltinLink
  deriving (Eq, Ord, Show)
