module ProjMajster.Recipe.Build
  ( lowerBuildPlan
  ) where

import qualified Data.Text as Text
import System.FilePath ((</>), (<.>))

import ProjMajster.Core
import ProjMajster.Recipe.Types
import ProjMajster.Plan.Types

lowerBuildPlan :: BuildPlan -> BuildRecipe
lowerBuildPlan plan = BuildRecipe
  { recipeSources = concatMap targetRecipeSources targets
  , recipeTargets = targets
  }
  where
    targets =
      map (targetRecipe (planContext plan)) (planTargets plan)

targetRecipe :: BuildContext -> ResolvedTarget -> TargetRecipe
targetRecipe context target = TargetRecipe
  { targetRecipeName = resolvedTargetName target
  , targetRecipeKind = resolvedTargetKind target
  , targetRecipeSources = sourceDiscoveries (resolvedTargetName target) target
  , targetRecipeTransforms = resolvedTargetTransforms target
  , targetRecipeDependencies = internalDependencies target
  , targetRecipeProductBase = targetOutput context target
  }

sourceDiscoveries :: TargetName -> ResolvedTarget -> [SourceDiscovery]
sourceDiscoveries owner target =
  [ SourceDiscovery
      { sourceDiscoveryOwner = owner
      , sourceDiscoveryPattern = pattern
      }
  | sourceSet <- resolvedTargetSourceSets target
  , pattern <- sourceSetPatterns sourceSet
  ]

internalDependencies :: ResolvedTarget -> [TargetName]
internalDependencies target =
  [ depTarget
  | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
  ]

targetOutput :: BuildContext -> ResolvedTarget -> FileRef
targetOutput context target = FileRef
  { fileRefPath =
      buildProductDir (contextBuildDirs context) </> targetOutputName target
  , fileRefRole = outputRole (resolvedTargetKind target)
  , fileRefLanguage = Nothing
  , fileRefOwner = Just (resolvedTargetName target)
  }

targetOutputName :: ResolvedTarget -> FilePath
targetOutputName target =
  case resolvedTargetKind target of
    Program ->
      targetNameString (resolvedTargetName target)
    SharedLibrary _ ->
      "lib" <> targetNameString (resolvedTargetName target) <.> "so"

outputRole :: TargetKind -> FileRole
outputRole Program = ProgramBinary
outputRole (SharedLibrary _) = SharedObject

targetNameString :: TargetName -> String
targetNameString (TargetName name) =
  Text.unpack name
