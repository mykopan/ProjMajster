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
program name = target
  (TargetName name)
  LinkProgram
  [ compileCTransform
  , compileCxxTransform
  , linkTransform [OutputFileMapping ProgramBinary (Text.unpack name)]
  ]

sharedLibrary :: Text -> TargetM () -> ProjectM ()
sharedLibrary name = target
  (TargetName name)
  LinkShared
  [ compileCTransform
  , compileCxxTransform
  , linkTransform [OutputFileMapping SharedObject ("lib" <> Text.unpack name <> ".so")]
  ]

aorpModule :: Text -> TargetM () -> ProjectM ()
aorpModule name = target
  (TargetName name)
  LinkShared
  [ compileCTransform
  , compileCxxTransform
  , linkTransform [OutputFileMapping SharedObject (Text.unpack name <> ".so")]
  ]

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

target :: TargetName -> LinkMode -> [TransformRule] -> TargetM () -> ProjectM ()
target name defaultLinkMode defaultTransforms body = ProjectM $
  modify $ \draft -> draft
    { projectDraftTargets =
        projectDraftTargets draft ++ [targetFromDraft targetDraft]
    }
  where
    userDraft = runTargetM name body
    targetDraft = userDraft
      { targetDraftTransforms =
          targetDraftTransforms userDraft ++ defaultTransforms
      , targetDraftSettings =
          setDefaultLinkMode defaultLinkMode (targetDraftSettings userDraft)
      }

sourceSetFromDraft :: SourceSetDraft -> SourceSet
sourceSetFromDraft draft = SourceSet
  { sourceSetName = Text.pack (sourceSetDraftName draft)
  , sourceSetPatterns = sourceSetDraftPatterns draft
  }

targetFromDraft :: TargetDraft -> Target
targetFromDraft draft = Target
  { targetName = targetDraftName draft
  , targetSourceSets = targetDraftSourceSets draft
  , targetTransforms = targetDraftTransforms draft
  , targetSettings = targetDraftSettings draft
  , targetInstallSpecs = targetDraftInstallSpecs draft
  }

setDefaultLinkMode :: LinkMode -> BuildSettings -> BuildSettings
setDefaultLinkMode defaultMode settings = settings
  { linkSettings = link
      { linkSettingsMode = linkSettingsMode link <|> Just defaultMode
      }
  }
  where
    link = ProjMajster.Core.linkSettings settings

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

linkTransform :: [OutputFileMapping] -> TransformRule
linkTransform outputs = TransformRule
  { transformName = TransformName "link"
  , transformKind = FoldTransform
  , transformInput = InputLinkInput
  , transformOutput = OutputFiles outputs
  , transformAction = BuiltinAction BuiltinLink
  }
