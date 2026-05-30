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

import Control.Applicative ((<|>))
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

instance Semigroup CommonSettings where
  lhs <> rhs = CommonSettings
    { commonDefines =
        commonDefines lhs <> commonDefines rhs
    , commonIncludeDirs =
        commonIncludeDirs lhs <> commonIncludeDirs rhs
    , commonWarningPolicy =
        commonWarningPolicy rhs <|> commonWarningPolicy lhs
    , commonDebugInfo =
        commonDebugInfo rhs <|> commonDebugInfo lhs
    , commonOptimization =
        commonOptimization rhs <|> commonOptimization lhs
    , commonPositionIndependentCode =
        commonPositionIndependentCode rhs <|> commonPositionIndependentCode lhs
    }

instance Monoid CommonSettings where
  mempty = emptyCommonSettings

data CSettings = CSettings
  { cSettingsStandard :: Maybe Text
  , cRawOptions :: [RawOption]
  } deriving (Eq, Show)

instance Semigroup CSettings where
  lhs <> rhs = CSettings
    { cSettingsStandard =
        cSettingsStandard rhs <|> cSettingsStandard lhs
    , cRawOptions =
        cRawOptions lhs <> cRawOptions rhs
    }

instance Monoid CSettings where
  mempty = emptyCSettings

data CxxSettings = CxxSettings
  { cxxSettingsStandard :: Maybe Text
  , cxxRawOptions :: [RawOption]
  } deriving (Eq, Show)

instance Semigroup CxxSettings where
  lhs <> rhs = CxxSettings
    { cxxSettingsStandard =
        cxxSettingsStandard rhs <|> cxxSettingsStandard lhs
    , cxxRawOptions =
        cxxRawOptions lhs <> cxxRawOptions rhs
    }

instance Monoid CxxSettings where
  mempty = emptyCxxSettings

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

instance Semigroup LinkSettings where
  lhs <> rhs = LinkSettings
    { linkSettingsMode =
        linkSettingsMode rhs <|> linkSettingsMode lhs
    , linkLibraries =
        linkLibraries lhs <> linkLibraries rhs
    , linkLibraryDirs =
        linkLibraryDirs lhs <> linkLibraryDirs rhs
    , linkRawOptions =
        linkRawOptions lhs <> linkRawOptions rhs
    }

instance Monoid LinkSettings where
  mempty = emptyLinkSettings

data BuildSettings = BuildSettings
  { commonSettings :: CommonSettings
  , cSettings :: CSettings
  , cxxSettings :: CxxSettings
  , linkSettings :: LinkSettings
  } deriving (Eq, Show)

instance Semigroup BuildSettings where
  lhs <> rhs = BuildSettings
    { commonSettings =
        commonSettings lhs <> commonSettings rhs
    , cSettings =
        cSettings lhs <> cSettings rhs
    , cxxSettings =
        cxxSettings lhs <> cxxSettings rhs
    , linkSettings =
        linkSettings lhs <> linkSettings rhs
    }

instance Monoid BuildSettings where
  mempty = emptyBuildSettings

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
