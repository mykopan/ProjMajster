module ProjMajster.DSL.Dependency
  ( binaryDep
  , binaryDepAt
  , depAspect
  ) where

import Control.Monad.State.Strict (modify)
import Data.Text (Text)

import ProjMajster.Core
import ProjMajster.DSL.Internal

binaryDep :: Text -> ProjectM ()
binaryDep name =
  addExternalDep ExternalDep
    { externalDepName = DepName name
    , externalDepVersion = AnyVersion
    , externalDepAspects = []
    }

binaryDepAt :: Text -> [Int] -> ProjectM ()
binaryDepAt name version =
  addExternalDep ExternalDep
    { externalDepName = DepName name
    , externalDepVersion = ExactVersion version
    , externalDepAspects = []
    }

depAspect :: Text -> Text -> ProjectM ()
depAspect name aspect =
  addExternalDep ExternalDep
    { externalDepName = DepName name
    , externalDepVersion = AnyVersion
    , externalDepAspects = [DepAspect aspect]
    }

addExternalDep :: ExternalDep -> ProjectM ()
addExternalDep dep = ProjectM $
  modify $ \draft -> draft
    { projectDraftExternalDeps = projectDraftExternalDeps draft ++ [dep]
    }
