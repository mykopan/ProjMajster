{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.Settings
  ( Optimization(..)
  , DebugInfo(..)
  , WarningPolicy(..)
  , RawOption(..)
  , LibraryName(..)
  , CommonSettings(..)
  , CSettings(..)
  , CxxSettings(..)
  , LinkMode(..)
  , LinkSettings(..)
  , BuildSettings(..)
  , emptyCommonSettings
  , emptyCSettings
  , emptyCxxSettings
  , emptyLinkSettings
  , emptyBuildSettings
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

data Optimization
  = NoOptimization
  | Optimize
  | OptimizeSize
  | OptimizeAggressively
  deriving (Eq, Ord, Show)

data DebugInfo
  = NoDebugInfo
  | MinimalDebugInfo
  | FullDebugInfo
  deriving (Eq, Ord, Show)

data WarningPolicy
  = DefaultWarnings
  | AllWarnings
  | WarningsAsErrors
  deriving (Eq, Ord, Show)

newtype RawOption = RawOption
  { rawOptionText :: Text
  } deriving (Eq, Ord, Show)

newtype LibraryName = LibraryName
  { libraryNameText :: Text
  } deriving (Eq, Ord, Show)

data CommonSettings = CommonSettings
  { commonDefines :: Map Text Text
  , commonIncludeDirs :: [FilePath]
  , commonWarningPolicy :: Maybe WarningPolicy
  , commonDebugInfo :: Maybe DebugInfo
  , commonOptimization :: Maybe Optimization
  , commonPositionIndependentCode :: Maybe Bool
  } deriving (Eq, Show)

data CSettings = CSettings
  { cSettingsStandard :: Maybe Text
  , cRawOptions :: [RawOption]
  } deriving (Eq, Show)

data CxxSettings = CxxSettings
  { cxxSettingsStandard :: Maybe Text
  , cxxRawOptions :: [RawOption]
  } deriving (Eq, Show)

data LinkMode
  = LinkProgram
  | LinkShared
  deriving (Eq, Ord, Show)

data LinkSettings = LinkSettings
  { linkSettingsMode :: Maybe LinkMode
  , linkLibraries :: [LibraryName]
  , linkLibraryDirs :: [FilePath]
  , linkRawOptions :: [RawOption]
  } deriving (Eq, Show)

data BuildSettings = BuildSettings
  { commonSettings :: CommonSettings
  , cSettings :: CSettings
  , cxxSettings :: CxxSettings
  , linkSettings :: LinkSettings
  } deriving (Eq, Show)

emptyCommonSettings :: CommonSettings
emptyCommonSettings = CommonSettings
  { commonDefines = Map.empty
  , commonIncludeDirs = []
  , commonWarningPolicy = Nothing
  , commonDebugInfo = Nothing
  , commonOptimization = Nothing
  , commonPositionIndependentCode = Nothing
  }

emptyCSettings :: CSettings
emptyCSettings = CSettings
  { cSettingsStandard = Nothing
  , cRawOptions = []
  }

emptyCxxSettings :: CxxSettings
emptyCxxSettings = CxxSettings
  { cxxSettingsStandard = Nothing
  , cxxRawOptions = []
  }

emptyLinkSettings :: LinkSettings
emptyLinkSettings = LinkSettings
  { linkSettingsMode = Nothing
  , linkLibraries = []
  , linkLibraryDirs = []
  , linkRawOptions = []
  }

emptyBuildSettings :: BuildSettings
emptyBuildSettings = BuildSettings
  { commonSettings = emptyCommonSettings
  , cSettings = emptyCSettings
  , cxxSettings = emptyCxxSettings
  , linkSettings = emptyLinkSettings
  }
