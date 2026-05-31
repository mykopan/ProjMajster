module ProjMajster.Recipe.Build
  ( lowerBuildPlan
  ) where

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
  , targetRecipeSources = sourceDiscoveries (resolvedTargetName target) target
  , targetRecipeTransforms = resolvedTargetTransforms target
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

internalDependencies :: ResolvedTarget -> [TargetName]
internalDependencies target =
  [ depTarget
  | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
  ]
