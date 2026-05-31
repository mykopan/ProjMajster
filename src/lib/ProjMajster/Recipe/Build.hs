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
  , targetRecipeTransforms = resolveTargetProductMappings context target
      (resolvedTargetTransforms target)
  , targetRecipeDependencies = internalDependencies target
  , targetRecipeProductDir = buildProductDir (contextBuildDirs context)
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

resolveTargetProductMappings :: BuildContext -> ResolvedTarget -> [TransformRule] -> [TransformRule]
resolveTargetProductMappings context target =
  map resolveRule
  where
    resolveRule rule =
      case transformOutput rule of
        OutputDefaultTargetProducts ->
          rule
            { transformOutput = OutputTargetProducts
                [ targetProductMapping context target
                ]
            }
        _ ->
          rule

targetProductMapping :: BuildContext -> ResolvedTarget -> ProductMapping
targetProductMapping context target = ProductMapping
  { productRole = outputRole (resolvedTargetKind target)
  , productPath = buildProductDir (contextBuildDirs context) </> targetOutputName target
  }

internalDependencies :: ResolvedTarget -> [TargetName]
internalDependencies target =
  [ depTarget
  | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
  ]

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
