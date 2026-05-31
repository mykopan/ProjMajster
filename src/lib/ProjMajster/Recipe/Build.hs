module ProjMajster.Recipe.Build
  ( lowerBuildPlan
  ) where

import System.FilePath ((</>))

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
resolveTargetProductMappings context _target =
  map resolveRule
  where
    resolveRule rule =
      case transformOutput rule of
        OutputDefaultTargetProducts products ->
          rule
            { transformOutput = OutputTargetProducts
                (map (targetProductMapping context) products)
            }
        _ ->
          rule

targetProductMapping :: BuildContext -> DefaultProductMapping -> ProductMapping
targetProductMapping context defaultProduct = ProductMapping
  { productRole = defaultProductRole defaultProduct
  , productPath = buildProductDir (contextBuildDirs context) </> defaultProductName defaultProduct
  }

internalDependencies :: ResolvedTarget -> [TargetName]
internalDependencies target =
  [ depTarget
  | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
  ]
