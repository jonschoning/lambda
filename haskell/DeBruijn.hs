module Lamb where

import Prelude hiding (foldr)
import Data.Foldable (foldr)
import Control.Applicative
import Data.List (elemIndex)

-- A simply-typed lambda calculator implemented with de Bruijn indexing
-- Rob Norris / @tpolecat

-- Identifiers are strings
type Ident = String

-- Types
data Type
  = TInt
  | TFun Type Type
  deriving (Show, Eq)

-- Surface syntax
data Surface
  = SVar Ident
  | SApp Surface Surface
  | SLam Type Ident Surface
  | SNum Int
  | SAdd Surface Surface
  deriving Show

-- Desugared, with de Bruijn indices
data Desugared
  = DBound Int
  | DApp Desugared Desugared
  | DLam Type Desugared
  | DNum Int
  | DBin (Int -> Int -> Int) Desugared Desugared

-- The function in DBin means we have to do this by hand
instance Show Desugared where
  show d = "(" ++ s ++ ")" where 
    s = case d of 
      DBound n   -> "DBound "     ++ show n
      DNum n     -> "DNum "       ++ show n
      DLam t a   -> "DLam "       ++ show t ++ " " ++ show a
      DApp a b   -> "DApp "       ++ show a ++ " " ++ show b
      DBin _ a b -> "DBin <fun> " ++ show a ++ " " ++ show b

-- We compute a value
data Value
  = VFun [Value] Desugared -- a closure
  | VNum Int
  deriving Show

-- But things can go wrong
data Error
  = Unbound  Ident
  | NotAFun  Desugared Type -- element, type
  | IllTyped Desugared Type Type -- element expected actual
  deriving Show

-- Why is this not in stdlib?
toEither :: b -> Maybe a -> Either b a
toEither b = foldr (const . Right) (Left b)

-- Desugar and replace all bound variables with de Bruijn indices, or
-- report an error if an unbound variable is encountered.
desugar :: [Ident] -> Surface -> Either Error Desugared
desugar e s = case s of
  SNum n     -> Right (DNum n)
  SVar i     -> DBound   <$> toEither (Unbound i) (elemIndex i e) 
  SLam t i a -> DLam t   <$> desugar (i : e) a
  SApp a b   -> DApp     <$> desugar e a <*> desugar e b
  SAdd a b   -> DBin (+) <$> desugar e a <*> desugar e b

-- Typechecker. With de Bruijn indices our type environment is simply a stack. 
typecheck :: [Type] -> Desugared -> Either Error Type
typecheck e d = case d of
  DNum n     -> Right TInt
  DBound n   -> Right (e !! n) -- safe due to desugaring
  DLam t a   -> TFun t <$> typecheck (t : e) a
  DBin _ a b -> 
    do ta <- typecheck e a
       tb <- typecheck e b
       case (ta, tb) of 
         (TInt, TInt) -> Right TInt
         (TInt, tb)   -> Left (IllTyped b TInt tb)
         (ta, _)      -> Left (IllTyped a TInt ta)
  DApp a b -> 
    do ta <- typecheck e a
       tb <- typecheck e b
       case ta of
         TFun x y | x == tb   -> Right y
         TFun x y | otherwise -> Left (IllTyped b x tb)
         x                    -> Left (NotAFun b x)

-- Evaluate a typechecked program, yielding a value or an error.
-- With de Bruijn indices our binding environment is simply a stack. 
eval :: [Value] -> Desugared -> Either Error Value
eval e d = case d of
  DNum n   -> Right (VNum n)
  DBound n -> Right (e !! n) -- safe due to desugaring
  DLam _ a -> Right (VFun e a)
  DBin f a b -> 
    do VNum a <- eval e a -- safe due to typechecking
       VNum b <- eval e b
       Right $ VNum (f a b) 
  DApp a b -> 
    do VFun e a <- eval e a -- safe due to typechecking
       b <- eval e b
       eval (b : e) a 

-- Desugar and evaluate a program in surface syntax
run :: Surface -> Either Error (Type, Value)
run p = do d <- desugar [] p 
           t <- typecheck [] d
           v <- eval [] d
           return (t, v)

-- Some example programs

xid = SLam TInt "a" (SVar "a") -- id
xconst = SLam TInt "a" $ SLam TInt "b" (SVar "a") -- const

xerr1 = SLam TInt "a" $ SLam TInt "b" (SVar "c") -- unbound
xerr2 = SApp (SNum 3) (SNum 3) -- not a function
xerr3 = SAdd xid xid -- not a number

xtest1 = SApp (SLam TInt "a" $ SAdd (SApp (SLam TInt "b" (SVar "a")) (SNum 2)) (SVar "a")) (SNum 3) -- (\a -> ((\b -> a) 2) + a) 3 --> 6
xtest2 = SApp (SLam (TFun TInt TInt) "f" (SApp (SVar "f") (SNum 1))) xid -- (\f -> f 1) id --> 1
xtest3 = SApp (SLam (TFun TInt TInt) "f" (SApp (SVar "f") (SNum 1))) (SApp xconst (SNum 10)) -- (\f -> f 1) (const 10) --> 10






