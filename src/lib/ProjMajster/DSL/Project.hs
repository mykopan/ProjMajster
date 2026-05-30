module ProjMajster.DSL.Project
  ( ProjectM
  , project
  , version
  , buildStyle
  , settings
  ) where

import Control.Monad.State.Strict (modify)
import Data.Text (Text)
import qualified Data.Map.Strict as Map

import ProjMajster.Core
import ProjMajster.DSL.Internal

project :: Text -> ProjectM () -> Project
project name body = projectFromDraft (runProjectM (ProjectName name) body)

version :: [Int] -> ProjectM ()
version value = ProjectM $
  modify $ \draft -> draft
    { projectDraftVersion = value
    }

buildStyle :: BuildStyle -> SettingsM () -> ProjectM ()
buildStyle style body = ProjectM $
  modify $ \draft -> draft
    { projectDraftBuildStyleSettings =
        Map.insert style (runSettingsM body) (projectDraftBuildStyleSettings draft)
    }

settings :: SettingsM () -> ProjectM ()
settings body = ProjectM $
  modify $ \draft -> draft
    { projectDraftDefaultSettings =
        applySettingsM (projectDraftDefaultSettings draft) body
    }

projectFromDraft :: ProjectDraft -> Project
projectFromDraft draft = Project
  { projectName = projectDraftName draft
  , projectVersion = projectDraftVersion draft
  , projectTargets = projectDraftTargets draft
  , projectExternalDeps = projectDraftExternalDeps draft
  , projectDefaultSettings = projectDraftDefaultSettings draft
  , projectBuildStyleSettings = projectDraftBuildStyleSettings draft
  }
