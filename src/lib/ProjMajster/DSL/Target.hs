{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.DSL.Target
  ( TargetM
  , program
  , sharedLibrary
  , aorpModule
  , sources
  , install
  ) where

import Control.Applicative ((<|>))
import Control.Monad.State.Strict (modify)
import Data.Text (Text)
import qualified Data.Text as Text

import ProjMajster.Core
import ProjMajster.DSL.Internal

program :: Text -> TargetM () -> ProjectM ()
program name =
  target (TargetName name) Program

sharedLibrary :: Text -> TargetM () -> ProjectM ()
sharedLibrary name =
  target (TargetName name) (SharedLibrary NormalSharedLibrary)

aorpModule :: Text -> TargetM () -> ProjectM ()
aorpModule name =
  target (TargetName name) (SharedLibrary style)
  where
    style = PluginSharedLibrary PluginStyle
      { pluginFileNamePolicy = PlatformFileName name
      , pluginInstallDir = CustomInstallDir ("libexec/aorp/modules")
      , pluginStubPolicy = NoStub
      }

sources :: FilePath -> SourceSetM () -> TargetM ()
sources baseDir body = TargetM $
  modify $ \draft -> draft
    { targetDraftSourceSets =
        targetDraftSourceSets draft ++ [sourceSetFromDraft sourceDraft]
    }
  where
    sourceDraft = runSourceSetM baseDir body

install :: InstallDir -> TargetM ()
install dir = TargetM $
  modify $ \draft -> draft
    { targetDraftInstallSpecs =
        targetDraftInstallSpecs draft ++
        [ InstallSpec
            { installSpecDir = dir
            , installSpecRole = Nothing
            }
        ]
    }

target :: TargetName -> TargetKind -> TargetM () -> ProjectM ()
target name kind body = ProjectM $
  modify $ \draft -> draft
    { projectDraftTargets =
        projectDraftTargets draft ++ [targetFromDraft targetDraft]
    }
  where
    targetDraft = runTargetM name kind body

sourceSetFromDraft :: SourceSetDraft -> SourceSet
sourceSetFromDraft draft = SourceSet
  { sourceSetName = Text.pack (sourceSetDraftName draft)
  , sourceSetPatterns = sourceSetDraftPatterns draft
  }

targetFromDraft :: TargetDraft -> Target
targetFromDraft draft = Target
  { targetName = targetDraftName draft
  , targetKind = targetDraftKind draft
  , targetSourceSets = targetDraftSourceSets draft
  , targetSettings = setDefaultLinkMode (targetDraftKind draft)
      (targetDraftSettings draft)
  , targetInstallSpecs = targetDraftInstallSpecs draft
  }

setDefaultLinkMode :: TargetKind -> BuildSettings -> BuildSettings
setDefaultLinkMode kind settings = settings
  { linkSettings = link
      { linkSettingsMode = linkSettingsMode link <|> defaultMode
      }
  }
  where
    link = ProjMajster.Core.linkSettings settings
    defaultMode = case kind of
      Program -> Just LinkProgram
      SharedLibrary _ -> Just LinkShared
