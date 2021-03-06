module Main where

import qualified BotSpec.BttvFfzSpec as BFS
import qualified CommandSpec as CS
import qualified Sqlite.EntityPersistenceSpec as SEPS
import           System.Exit
import           Test.HUnit

main :: IO Counts
main = do results <- runTestTT $ TestList [ BFS.parseCorrectBttvEmoteList
                                          , BFS.parseCorrectFfzEmoteList
                                          , CS.commandWithGermanUmlauts
                                          , CS.commandWithRussians
                                          , SEPS.createEntityAndGetItById
                                          , SEPS.createSeveralEntityTypes
                                          , SEPS.deleteEntitiesWithPropertyEquals
                                          , SEPS.getRandomEntityIdWithPropertyEquals
                                          , SEPS.nextEntityId
                                          , SEPS.selectEntitiesWithPropertyEquals
                                          , SEPS.doublePrepareSchemaSpec
                                          ]
          if errors results + failures results == 0
          then exitSuccess
          else exitWith (ExitFailure 1)
