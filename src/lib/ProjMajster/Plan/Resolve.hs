module ProjMajster.Plan.Resolve
  ( resolveProject
  ) where

import Data.List (find, group, sort)
import Data.Foldable (traverse_)
import qualified Data.Map.Strict as Map

import ProjMajster.Core
import ProjMajster.Plan.Error
import ProjMajster.Plan.Types

resolveProject :: BuildContext -> Project -> Either PlanError BuildPlan
resolveProject context project = do
  validateProject project
  styleSettings <- lookupBuildStyleSettings (contextBuildStyle context) project
  let projectSettings = projectDefaultSettings project <> styleSettings
  let internalTargetNames = map targetName (projectTargets project)
  pure BuildPlan
    { planContext = context
    , planTargets =
        map (resolveTarget internalTargetNames projectSettings)
          (projectTargets project)
    , planExternalDeps = []
    , planInstallSpecs =
        concatMap targetInstallSpecs (projectTargets project)
    }

validateProject :: Project -> Either PlanError ()
validateProject project = do
  validateProjectName (projectName project)
  traverse_ validateTargetName targetNames
  case duplicateTargetName targetNames of
    Just target -> Left (DuplicateTargetName target)
    Nothing -> Right ()
  where
    targetNames = map targetName (projectTargets project)

validateProjectName :: ProjectName -> Either PlanError ()
validateProjectName (ProjectName name)
  | name == mempty = Left EmptyProjectName
  | otherwise = Right ()

validateTargetName :: TargetName -> Either PlanError ()
validateTargetName (TargetName name)
  | name == mempty = Left EmptyTargetName
  | otherwise = Right ()

duplicateTargetName :: [TargetName] -> Maybe TargetName
duplicateTargetName =
  fmap head . findDuplicateGroup . group . sort

findDuplicateGroup :: [[a]] -> Maybe [a]
findDuplicateGroup = find ((1 <) . length)

lookupBuildStyleSettings :: BuildStyle -> Project -> Either PlanError BuildSettings
lookupBuildStyleSettings style project =
  case Map.lookup style (projectBuildStyleSettings project) of
    Just settings -> Right settings
    Nothing
      | Map.null (projectBuildStyleSettings project) -> Right mempty
      | otherwise -> Left (UnknownBuildStyle style)

resolveTarget :: [TargetName] -> BuildSettings -> Target -> ResolvedTarget
resolveTarget internalTargetNames projectSettings target = ResolvedTarget
  { resolvedTargetName = targetName target
  , resolvedTargetKind = targetKind target
  , resolvedTargetSourceSets = targetSourceSets target
  , resolvedTargetSettings =
      projectSettings <> targetSettings target
  , resolvedTargetDeps =
      inferInternalDeps internalTargetNames target
  , resolvedTargetInstallSpecs = targetInstallSpecs target
  }

inferInternalDeps :: [TargetName] -> Target -> [Dependency]
inferInternalDeps internalTargetNames target =
  [ InternalDependency (InternalDep targetName')
  | library <- linkLibraries (linkSettings (targetSettings target))
  , targetName' <- internalTargetNames
  , libraryMatchesTarget library targetName'
  , targetName' /= targetName target
  ]

libraryMatchesTarget :: LibraryName -> TargetName -> Bool
libraryMatchesTarget (LibraryName libraryName) (TargetName targetName') =
  libraryName == targetName'
