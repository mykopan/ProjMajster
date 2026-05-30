{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.DSL.Target
  ( TargetM
  , program
  , sharedLibrary
  , aorpModule
  , sources
  , transform
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
  target (TargetName name) Program [compileCTransform, compileCxxTransform, linkTransform]

sharedLibrary :: Text -> TargetM () -> ProjectM ()
sharedLibrary name =
  target
    (TargetName name)
    (SharedLibrary NormalSharedLibrary)
    [compileCTransform, compileCxxTransform, linkTransform]

aorpModule :: Text -> TargetM () -> ProjectM ()
aorpModule name =
  target (TargetName name) (SharedLibrary style)
    [compileCTransform, compileCxxTransform, linkTransform]
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

transform :: TransformRule -> TargetM ()
transform rule = TargetM $
  modify $ \draft -> draft
    { targetDraftTransforms =
        targetDraftTransforms draft ++ [rule]
    }

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

target :: TargetName -> TargetKind -> [TransformRule] -> TargetM () -> ProjectM ()
target name kind defaultTransforms body = ProjectM $
  modify $ \draft -> draft
    { projectDraftTargets =
        projectDraftTargets draft ++ [targetFromDraft targetDraft]
    }
  where
    userDraft = runTargetM name kind body
    targetDraft = userDraft
      { targetDraftTransforms =
          targetDraftTransforms userDraft ++ defaultTransforms
      }

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
  , targetTransforms = targetDraftTransforms draft
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

compileCTransform :: TransformRule
compileCTransform = TransformRule
  { transformName = TransformName "compile-c"
  , transformKind = MapTransform
  , transformInput = InputLanguage C
  , transformOutput = OutputObject
  , transformAction = BuiltinAction BuiltinCompileC
  }

compileCxxTransform :: TransformRule
compileCxxTransform = TransformRule
  { transformName = TransformName "compile-cxx"
  , transformKind = MapTransform
  , transformInput = InputLanguage Cxx
  , transformOutput = OutputObject
  , transformAction = BuiltinAction BuiltinCompileCxx
  }

linkTransform :: TransformRule
linkTransform = TransformRule
  { transformName = TransformName "link"
  , transformKind = FoldTransform
  , transformInput = InputLinkInput
  , transformOutput = OutputTargetProducts []
  , transformAction = BuiltinAction BuiltinLink
  }
