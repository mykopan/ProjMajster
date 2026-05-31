{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.FileRole
  ( FileRole(..)
  ) where

import Data.Text (Text)

data FileRole
  = SourceFile
  | GeneratedSource
  | GeneratedHeader
  | ObjectFile
  | ProgramBinary
  | SharedObject
  | ImportLibrary
  | DebugSymbols
  | Manifest
  | InstalledFile
  | PackageFile
  | CustomFileRole Text
  deriving (Eq, Ord, Show, Read)
