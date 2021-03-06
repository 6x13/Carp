{-# LANGUAGE FlexibleContexts #-}

module Parsing (parse, validCharacters, balance) where

import Text.Parsec ((<|>))
import qualified Text.Parsec as Parsec
import qualified Data.Set as Set
import Obj
import Types

newtype ParseState = ParseState { parseInfo :: Info }

bumpIdentifier :: Parsec.Parsec String ParseState ()
bumpIdentifier = do i <- fmap parseInfo Parsec.getState
                    let current = infoIdentifier i
                    Parsec.putState (ParseState (i { infoIdentifier = current + 1 }))

createInfo :: Parsec.Parsec String ParseState (Maybe Info)
createInfo = do i <- fmap parseInfo Parsec.getState
                bumpIdentifier
                return (Just i)

firstDigit :: Parsec.Parsec String ParseState Char
firstDigit = Parsec.choice [Parsec.digit, Parsec.char '-']

double :: Parsec.Parsec String ParseState XObj
double = do i <- createInfo
            num0 <- firstDigit
            num1 <- Parsec.many Parsec.digit
            let num = num0 : num1
            incColumn (length num)
            _ <- Parsec.char '.'
            decimals <- Parsec.many1 Parsec.digit
            incColumn (length decimals)
            if num == "-"
              then return (XObj (Sym (SymPath [] "-")) i Nothing)
              else return (XObj (Num DoubleTy (read (num ++ "." ++ decimals))) i Nothing)

float :: Parsec.Parsec String ParseState XObj
float = do i <- createInfo
           num0 <- firstDigit
           num1 <- Parsec.many Parsec.digit
           let num = num0 : num1
           incColumn (length num)
           _ <- Parsec.char '.'
           incColumn 1
           decimals <- Parsec.many1 Parsec.digit
           incColumn (length decimals)
           _ <- Parsec.char 'f'
           incColumn 1
           if num == "-"
             then return (XObj (Sym (SymPath [] "-")) i Nothing)
             else return (XObj (Num FloatTy (read (num ++ "." ++ decimals))) i Nothing)

integer :: Parsec.Parsec String ParseState XObj
integer = do i <- createInfo
             num0 <- firstDigit
             num1 <- Parsec.many Parsec.digit
             let num = num0 : num1
             incColumn (length num)
             if num == "-"
               then return (XObj (Sym (SymPath [] "-")) i Nothing)
               else return (XObj (Num IntTy (read num)) i Nothing)

number :: Parsec.Parsec String ParseState XObj
number = Parsec.try float <|>
         Parsec.try double <|>
         Parsec.try integer

string :: Parsec.Parsec String ParseState XObj
string = do i <- createInfo
            _ <- Parsec.char '"'
            str <- Parsec.many (Parsec.noneOf ['"'])
            _ <- Parsec.char '"'
            incColumn (length str + 2)
            return (XObj (Str str) i Nothing)

aChar :: Parsec.Parsec String ParseState XObj
aChar = do i <- createInfo
           _ <- Parsec.char '\\'
           c <- Parsec.anyChar
           incColumn 2
           return (XObj (Chr c) i Nothing)

validCharacters :: [Char]
validCharacters = "+-*/?!><=_:"

symbolSegment :: Parsec.Parsec String ParseState String
symbolSegment = do sym <- Parsec.many1 validInSymbol
                   incColumn (length sym)
                   return sym
  where validInSymbol = Parsec.choice [Parsec.letter, Parsec.digit, Parsec.oneOf validCharacters]
  
symbol :: Parsec.Parsec String ParseState XObj
symbol = do i <- createInfo
            segments <- Parsec.sepBy1 symbolSegment (Parsec.char '.')
            case last segments of
              "defn" -> return (XObj Defn i Nothing)
              "def" -> return (XObj Def i Nothing)
              -- What about the other def- forms?
              "do" -> return (XObj Do i Nothing)
              "while" -> return (XObj While i Nothing)
              -- "fn" -> return (XObj Fn i Nothing)
              "let" -> return (XObj Let i Nothing)
              "if" -> return (XObj If i Nothing)
              "true" -> return (XObj (Bol True) i Nothing)
              "false" -> return (XObj (Bol False) i Nothing)
              "address" -> return (XObj Address i Nothing)
              "set!" -> return (XObj SetBang i Nothing)
              "the" -> return (XObj The i Nothing)
              "ref" -> return (XObj Ref i Nothing)
              name   -> return (XObj (Sym (SymPath (init segments) name)) i Nothing)
                        
atom :: Parsec.Parsec String ParseState XObj
atom = Parsec.choice [number, string, aChar, symbol]

incColumn :: Int -> Parsec.Parsec String ParseState ()
incColumn x = do s <- Parsec.getState
                 let i = parseInfo s
                     line = infoLine i
                     column = infoColumn i
                     identifier = infoIdentifier i
                     newInfo = Info line (column + x) (Set.fromList []) identifier
                 Parsec.putState (s { parseInfo = newInfo })
                 return ()

comment :: Parsec.Parsec String ParseState ()
comment = do _ <- Parsec.char ';'
             _ <- Parsec.many (Parsec.noneOf ['\n'])
             return ()

linebreak :: Parsec.Parsec String ParseState ()
linebreak = do s <- Parsec.getState
               let i = parseInfo s
                   line = infoLine i
                   identifier = infoIdentifier i
                   newInfo = Info (line + 1) 0 (Set.fromList [])  identifier
               Parsec.putState (s { parseInfo = newInfo })
               _ <- Parsec.char '\n'
               return ()

space :: Parsec.Parsec String ParseState ()
space = do incColumn 1
           _ <- Parsec.char ' '
           return ()

tab :: Parsec.Parsec String ParseState ()
tab = do incColumn 1
         _ <- Parsec.char '\t'
         return ()

eof :: Parsec.Parsec String ParseState ()
eof = do _ <- Parsec.char '\0'
         return ()

emptyCharacters :: [Parsec.Parsec String ParseState ()]
emptyCharacters = [space, tab, linebreak, eof, comment]
           
whitespace :: Parsec.Parsec String ParseState ()
whitespace = do _ <- Parsec.many1 (Parsec.choice emptyCharacters)
                return ()

whitespaceOrNothing :: Parsec.Parsec String ParseState ()
whitespaceOrNothing = do _ <- Parsec.many (Parsec.choice emptyCharacters)
                         return ()

readObjs :: Parsec.Parsec String ParseState [XObj]
readObjs = do padding <- Parsec.many whitespace
              incColumn (length padding)
              Parsec.many sexpr
                         
array :: Parsec.Parsec String ParseState XObj
array = do i <- createInfo
           _ <- Parsec.char '['
           incColumn 1              
           objs <- readObjs
           _ <- Parsec.char ']'
           incColumn 1
           return (XObj (Arr objs) i Nothing)

list :: Parsec.Parsec String ParseState XObj
list = do i <- createInfo
          _ <- Parsec.char '('
          incColumn 1              
          objs <- readObjs
          _ <- Parsec.char ')'
          incColumn 1
          return (XObj (Lst objs) i Nothing)

ref :: Parsec.Parsec String ParseState XObj
ref = do i <- createInfo
         _ <- Parsec.char '&'
         expr <- sexpr
         return (XObj (Lst [(XObj Ref Nothing Nothing), expr]) i Nothing)

copy :: Parsec.Parsec String ParseState XObj
copy = do i1 <- createInfo
          i2 <- createInfo
          _ <- Parsec.char '@'
          expr <- sexpr
          return (XObj (Lst [(XObj (Sym (SymPath [] "copy")) i1 Nothing), expr]) i2 Nothing)
  
sexpr :: Parsec.Parsec String ParseState XObj
sexpr = do x <- Parsec.choice [ref, copy, list, array, atom]
           _ <- whitespaceOrNothing
           return x

lispSyntax :: Parsec.Parsec String ParseState [XObj]
lispSyntax = do padding <- Parsec.many whitespace
                incColumn (length padding)
                Parsec.sepBy sexpr whitespaceOrNothing

parse :: String -> Either Parsec.ParseError [XObj]
parse text = let initState = ParseState (Info 1 0 (Set.fromList []) 0)
             in  Parsec.runParser lispSyntax initState "(source)" text



-- | For detecting the parenthesis balance in a string, i.e. "((( ))" = 1
balance :: String -> Int
balance text =
  case Parsec.runParser parenSyntax [] "(parens)" text of
    Left err -> error (show err)
    Right ok -> ok
                    
  where parenSyntax :: Parsec.Parsec String [Char] Int
        parenSyntax = do _ <- Parsec.many character
                         parens <- Parsec.getState 
                         return (length parens)

        character :: Parsec.Parsec String [Char] ()
        character = do c <- Parsec.anyChar
                       parens <- Parsec.getState
                       case parens of
                         [] -> push c
                         '"':xs -> case c of
                                     '"' -> Parsec.putState xs -- close string
                                     _ -> return () -- inside string
                         (x:xs) -> case (x, c) of
                                     ('(', ')') -> Parsec.putState xs
                                     ('[', ']') -> Parsec.putState xs
                                     ('"', '"') -> Parsec.putState xs
                                     --('\\', _) -> Parsec.putState xs -- ignore char after '\'
                                     _ -> push c
                                     
        push :: Char -> Parsec.Parsec String String ()
        push c =
          do parens <- Parsec.getState
             case c of
               '(' -> Parsec.putState (c : parens)
               '[' -> Parsec.putState (c : parens)
               '"' -> Parsec.putState (c : parens)
               _ -> return ()
