{-# LANGUAGE UndecidableInstances #-}
module Zeno.Term (
  Term (..), Alt (..),
  TermSubstitution,
  isVar, fromVar, isApp, isCse, isLam, isFix,
  flattenApp, unflattenApp, flattenLam, unflattenLam,
  function, isNormal
) where

import Prelude ()
import Zeno.Prelude
import Zeno.Name ( Name )
import Zeno.Traversing
import Zeno.Utils
import Zeno.Type ( Type, Typed (..) )
import Zeno.Unification

import qualified Zeno.Type as Type
import qualified Data.Map as Map
import qualified Data.Set as Set

data Term a 
  = Var !a 
  | App !(Term a) !(Term a)
  | Lam !a !(Term a)
  | Fix !a !(Term a)
  | Cse     { caseOfName :: !Name,
              caseOfFixes :: !(Set a),
              caseOfTerm :: !(Term a),
              caseOfAlts :: ![Alt a] }
  deriving ( Eq, Ord, Foldable )
  
data Alt a
  = Alt     { altCon :: !a,
              altVars :: ![a],
              altTerm :: !(Term a) }
  deriving ( Eq, Ord, Foldable )
  
type TermSubstitution a = Substitution (Term a) (Term a)

instance HasVariables (Term a) where
  type Var (Term a) = a
  
  freeVars (App e1 e2) = freeVars e1 ++ freeVars e2
  freeVars (Var x) = Set.singleton x
  freeVars (Lam x e) = Set.delete x (freeVars e) 
  freeVars (Fix f e) = Set.delete f (freeVars e)
  freeVars cse@(Cse {}) =
    freeVars (caseOfTerm cse) ++ altVars
    where
    altVars = caseOfAlts cse |> map freeVars |> Set.unions
  
instance HasVariables (Alt a) where
  type Var (Alt a) = a
  
  freeVars (Alt _ vars e) = 
    Set.difference (freeVars e) (Set.fromList vars)

isVar :: Term a -> Bool
isVar (Var {}) = True
isVar _ = False

isApp :: Term a -> Bool
isApp (App {}) = True
isApp _ = False

isCse :: Term a -> Bool
isCse (Cse {}) = True
isCse _ = False

isLam :: Term a -> Bool
isLam (Lam {}) = True
isLam _ = False

isFix :: Term a -> Bool
isFix (Fix {}) = True
isFix _ = False

isNormal :: forall a . Term a -> Bool
isNormal = getAny . foldWithin anyFixedCases
  where
  anyFixedCases :: Term a -> Any
  anyFixedCases cse@(Cse {}) = Any . not . Set.null . caseOfFixes $ cse
  anyFixedCases _ = mempty

fromVar :: Term a -> a
fromVar (Var v) = v

function :: Term a -> Maybe a
function (flattenApp -> (Var x : _)) = Just x
function _ = Nothing

flattenApp :: Term a -> [Term a]
flattenApp (App lhs rhs) = flattenApp lhs ++ [rhs]
flattenApp expr = [expr]

unflattenApp :: [Term a] -> Term a
unflattenApp = foldl1 App

flattenLam :: Term a -> ([a], Term a)
flattenLam (Lam v rhs) = 
  let (vs, rhs') = flattenLam rhs in (v : vs, rhs')
flattenLam expr = ([], expr)

unflattenLam :: [a] -> Term a -> Term a
unflattenLam = flip (foldr Lam)

instance Ord a => Unifiable (Term a) where
  type UniTerm (Term a) = Term a
  type UniVar (Term a) = a

  unifier (Var v1) (Var v2)
    | v1 == v2 = mempty
  unifier (App f1 a1) (App f2 a2) =
    unifier f1 f2 `mappend` unifier a1 a2
  unifier (Lam v1 x1) (Lam v2 x2)
    | v1 == v2 = unifier x1 x2
  unifier (Fix v1 x1) (Fix v2 x2)
    | v1 == v2 = unifier x1 x2
  unifier x1 x2 
    | x1 == x2 = mempty
  unifier (Var x) expr =
    Unifier (Map.singleton x expr)
  unifier _ _ = error "need to implement unification for case"  --NoUnifier
  
  applyUnifier sub =
    substitute (Map.mapKeysMonotonic Var sub)

instance WithinTraversable (Term a) (Term a) where
  mapWithinM f (App lhs rhs) =
    f =<< return App `ap` mapWithinM f lhs `ap` mapWithinM f rhs
  mapWithinM f (Cse id fxs lhs alts) =
    f =<< return (Cse id fxs) `ap` mapWithinM f lhs 
                              `ap` mapM (mapWithinM f) alts
  mapWithinM f (Lam var rhs) =
    f =<< return (Lam var) `ap` mapWithinM f rhs
  mapWithinM f (Fix var rhs) =
    f =<< return (Fix var) `ap` mapWithinM f rhs
  mapWithinM f expr =
    f =<< return expr

instance WithinTraversable (Term a) (Alt a) where
  mapWithinM f (Alt con binds rhs) = 
    return (Alt con binds) `ap` mapWithinM f rhs
    
instance (Eq (SimpleType a), Typed a) => Typed (Term a) where
  type SimpleType (Term a) = SimpleType a

  typeOf (Var x) = typeOf x
  typeOf (Fix f _) = typeOf f
  typeOf cse@(Cse {}) = typeOf . altTerm . head  .caseOfAlts $ cse
  typeOf (Lam x e) = Type.Fun (typeOf x) (typeOf e)
  typeOf (App e1 e2)
    | typeOf e2 /= t1a = error "Argument types do not match"
    | otherwise = t1r
    where
    Type.Fun t1a t1r = typeOf e1
  
isOperator :: String -> Bool
isOperator | error "find where isOperator should go" = any (not . isNormalChar)
  where
  isNormalChar :: Char -> Bool
  isNormalChar '_' = True
 -- isNormalChar '$' = True
  isNormalChar '.' = True
  isNormalChar c = isAlphaNum c

