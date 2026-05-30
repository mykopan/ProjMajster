module ProjMajster.DSL.Settings
  ( MonadSettings(..)
  , SettingsM
  , define
  , includeDir
  , includeDirs
  , optimization
  , debugInfo
  , warningPolicy
  , pic
  , cStandard
  , cxxStandard
  , rawCOption
  , rawCxxOption
  , rawLinkOption
  , usesLib
  , usesLibs
  , libraryDir
  , libraryDirs
  ) where

import Control.Monad.State.Strict (modify)
import Data.Text (Text)
import qualified Data.Map.Strict as Map

import ProjMajster.Core
import ProjMajster.DSL.Internal

class Monad m => MonadSettings m where
  modifyBuildSettings :: (BuildSettings -> BuildSettings) -> m ()

instance MonadSettings SettingsM where
  modifyBuildSettings f = SettingsM (modify f)

instance MonadSettings TargetM where
  modifyBuildSettings f = TargetM $
    modify $ \draft -> draft
      { targetDraftSettings = f (targetDraftSettings draft)
      }

define :: MonadSettings m => Text -> Text -> m ()
define name value =
  modifyCommonSettings $ \settings -> settings
    { commonDefines = Map.insert name value (commonDefines settings)
    }

includeDir :: MonadSettings m => FilePath -> m ()
includeDir path =
  modifyCommonSettings $ \settings -> settings
    { commonIncludeDirs = commonIncludeDirs settings ++ [path]
    }

includeDirs :: MonadSettings m => [FilePath] -> m ()
includeDirs = mapM_ includeDir

optimization :: MonadSettings m => Optimization -> m ()
optimization value =
  modifyCommonSettings $ \settings -> settings
    { commonOptimization = Just value
    }

debugInfo :: MonadSettings m => DebugInfo -> m ()
debugInfo value =
  modifyCommonSettings $ \settings -> settings
    { commonDebugInfo = Just value
    }

warningPolicy :: MonadSettings m => WarningPolicy -> m ()
warningPolicy value =
  modifyCommonSettings $ \settings -> settings
    { commonWarningPolicy = Just value
    }

pic :: MonadSettings m => Bool -> m ()
pic value =
  modifyCommonSettings $ \settings -> settings
    { commonPositionIndependentCode = Just value
    }

cStandard :: MonadSettings m => Text -> m ()
cStandard value =
  modifyCSettings $ \settings -> settings
    { cSettingsStandard = Just value
    }

cxxStandard :: MonadSettings m => Text -> m ()
cxxStandard value =
  modifyCxxSettings $ \settings -> settings
    { cxxSettingsStandard = Just value
    }

rawCOption :: MonadSettings m => Text -> m ()
rawCOption value =
  modifyCSettings $ \settings -> settings
    { cRawOptions = cRawOptions settings ++ [RawOption value]
    }

rawCxxOption :: MonadSettings m => Text -> m ()
rawCxxOption value =
  modifyCxxSettings $ \settings -> settings
    { cxxRawOptions = cxxRawOptions settings ++ [RawOption value]
    }

rawLinkOption :: MonadSettings m => Text -> m ()
rawLinkOption value =
  modifyLinkSettings $ \settings -> settings
    { linkRawOptions = linkRawOptions settings ++ [RawOption value]
    }

usesLib :: MonadSettings m => Text -> m ()
usesLib name =
  modifyLinkSettings $ \settings -> settings
    { linkLibraries = linkLibraries settings ++ [LibraryName name]
    }

usesLibs :: MonadSettings m => [Text] -> m ()
usesLibs = mapM_ usesLib

libraryDir :: MonadSettings m => FilePath -> m ()
libraryDir path =
  modifyLinkSettings $ \settings -> settings
    { linkLibraryDirs = linkLibraryDirs settings ++ [path]
    }

libraryDirs :: MonadSettings m => [FilePath] -> m ()
libraryDirs = mapM_ libraryDir

modifyCommonSettings :: MonadSettings m => (CommonSettings -> CommonSettings) -> m ()
modifyCommonSettings f =
  modifyBuildSettings $ \settings -> settings
    { commonSettings = f (commonSettings settings)
    }

modifyCSettings :: MonadSettings m => (CSettings -> CSettings) -> m ()
modifyCSettings f =
  modifyBuildSettings $ \settings -> settings
    { cSettings = f (cSettings settings)
    }

modifyCxxSettings :: MonadSettings m => (CxxSettings -> CxxSettings) -> m ()
modifyCxxSettings f =
  modifyBuildSettings $ \settings -> settings
    { cxxSettings = f (cxxSettings settings)
    }

modifyLinkSettings :: MonadSettings m => (LinkSettings -> LinkSettings) -> m ()
modifyLinkSettings f =
  modifyBuildSettings $ \settings -> settings
    { linkSettings = f (linkSettings settings)
    }
