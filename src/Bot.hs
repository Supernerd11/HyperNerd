{-# LANGUAGE OverloadedStrings #-}
module Bot (Bot, bot, Event(..), Sender(..), TwitchStream(..)) where

import           Bot.BttvFfz
import           Bot.CustomCommand
import           Bot.Log
import           Bot.Periodic
import           Bot.Poll
import           Bot.Quote
import           Bot.Replies
import           Bot.Russify
import           Bot.Twitch
import           Command
import           Control.Applicative
import           Data.Char
import           Data.List
import qualified Data.Map as M
import           Data.Maybe
import qualified Data.Text as T
import           Effect
import           Events
import           Text.Printf
import           Text.Regex

type Bot = Event -> Effect ()

builtinCommands :: CommandTable T.Text
builtinCommands =
    M.fromList [ ("russify", ("Russify western spy text", russifyCommand))
               , ("addquote", ("Add quote to quote database",
                               authorizeCommand [ "tsoding"
                                                , "r3x1m"
                                                , "bpaf"
                                                , "voldyman"
                                                ] addQuoteCommand))
               , ("quote", ("Get a quote from the quote database", quoteCommand))
               , ("bttv", ("Show all available BTTV emotes", bttvCommand))
               , ("ffz", ("Show all available FFZ emotes", ffzCommand))

               , ("help", ("Send help", helpCommand builtinCommands))
               , ("poll", ("Starts a poll", authorizeCommand [ "tsoding"
                                                             , "r3x1m"
                                                             ]
                                            $ wordsArgsCommand pollCommand))
               , ("vote", ("Vote for a poll option", voteCommand))
               , ("uptime", ("Show stream uptime", uptimeCommand))
               , ("rq", ("Get random quote from your log", randomLogRecordCommand))
               , ("nope", ("Timeout yourself for 1 second", \sender _ -> say
                                                                           $ T.pack
                                                                           $ printf "/timeout %s 1"
                                                                           $ senderName sender))
               , ("addperiodic", ("Add periodic message", authorizeCommand [ "tsoding"
                                                                           , "r3x1m"
                                                                           ]
                                                            $ \sender message -> do addPeriodicMessage sender message
                                                                                    replyToUser (senderName sender)
                                                                                                "Added the periodic message"))
               , ("addcmd", ("Add custom command", authorizeCommand [ "tsoding"
                                                                    , "r3x1m"
                                                                    ]
                                                     $ regexArgsCommand "([a-zA-Z0-9]+) ?(.*)"
                                                     $ pairArgsCommand
                                                     $ addCustomCommand builtinCommands))
               , ("delcmd", ("Delete custom command", authorizeCommand ["tsoding", "r3x1m"]
                                                        $ deleteCustomCommand builtinCommands))
               ]

authorizeCommand :: [T.Text] -> CommandHandler a -> CommandHandler a
authorizeCommand authorizedPeople commandHandler sender args =
    if senderName sender `elem` authorizedPeople
    then commandHandler sender args
    else replyToUser (senderName sender)
                     "You are not authorized to use this command! HyperNyard"

pairArgsCommand :: CommandHandler (a, a) -> CommandHandler [a]
pairArgsCommand commandHandler sender [x, y] = commandHandler sender (x, y)
pairArgsCommand _ sender args =
    replyToUser (senderName sender)
      $ T.pack
      $ printf "Expected two arguments but got %d"
      $ length args

regexArgsCommand :: String -> CommandHandler [T.Text] -> CommandHandler T.Text
regexArgsCommand regexString commandHandler sender args =
    maybe (replyToUser (senderName sender)
             $ T.pack
             $ printf "Command doesn't match '%s' regex" regexString)
          (commandHandler sender . map T.pack)
      $ matchRegex (mkRegex regexString)
      $ T.unpack args

wordsArgsCommand :: CommandHandler [T.Text] -> CommandHandler T.Text
wordsArgsCommand commandHandler sender args =
    commandHandler sender $ T.words args

-- TODO(#146): textContainsLink doesn't recognize URLs without schema
textContainsLink :: T.Text -> Bool
textContainsLink t = isJust
                       $ matchRegex (mkRegex "[-a-zA-Z0-9@:%._\\+~#=]{2,256}\\.[a-z]{2,6}\\b([-a-zA-Z0-9@:%_\\+.~#?&\\/\\/=]*)")
                       $ T.unpack t

senderIsPleb :: Sender -> Bool
senderIsPleb sender = not (senderSubscriber sender) && not (senderMod sender)

forbidLinksForPlebs :: Event -> Maybe (Effect())
forbidLinksForPlebs (Msg sender text)
    | textContainsLink text && senderIsPleb sender =
        -- TODO(#147): use CLEARCHAT command instead of /timeout
        return $ do say $ T.pack $ printf "/timeout %s 1" $ senderName sender
                    replyToUser (senderName sender)
                                "Only subs can post links, sorry."
    | otherwise = Nothing
forbidLinksForPlebs _ = Nothing

textContainsWords :: [T.Text] -> T.Text -> Bool
textContainsWords banwords text =
    any (`elem` banwords)
      $ map (T.filter isAlpha . T.toLower)
      $ T.words text

helsinkiFilter :: Event -> Maybe (Effect ())
helsinkiFilter (Msg sender text)
    | textContainsWords [] text =
        return $ do say $ T.pack $ printf "/timeout %s 300" $ senderName sender
                    replyToUser (senderName sender) "Jebaited"
    | otherwise = Nothing
helsinkiFilter _ = Nothing

bot :: Bot
bot Join = startPeriodicMessages
bot event@(Msg sender text) =
    fromMaybe (do recordUserMsg sender text
                  maybe (return ())
                        (dispatchCommand sender)
                        (textAsCommand text))
              (helsinkiFilter event <|> forbidLinksForPlebs event)

helpCommand :: CommandTable T.Text -> CommandHandler T.Text
helpCommand commandTable sender "" =
    replyToUser (senderName sender)
      $ T.pack
      $ printf "Available commands: %s"
      $ T.concat
      $ intersperse (T.pack ", ")
      $ map (\x -> T.concat [T.pack "!", x])
      $ M.keys commandTable
helpCommand commandTable sender command =
    maybe (replyToUser (senderName sender) "Cannot find your stupid command HyperNyard")
          (replyToUser (senderName sender))
          (fst <$> M.lookup command commandTable)

dispatchCommand :: Sender -> Command T.Text -> Effect ()
dispatchCommand sender cmd =
    do dispatchBuiltinCommand sender cmd
       dispatchCustomCommand sender cmd

dispatchBuiltinCommand :: Sender -> Command T.Text -> Effect ()
dispatchBuiltinCommand sender command =
    maybe (return ())
          (\(_, f) -> f sender $ commandArgs command)
          (M.lookup (commandName command) builtinCommands)
