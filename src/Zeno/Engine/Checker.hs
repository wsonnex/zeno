module Zeno.Engine.Checker (
  explore, guessContext
) where

import Prelude ()
import Zeno.Prelude
import Zeno.Traversing
import Zeno.Unification
import Zeno.Var ( ZTerm, ZType, ZVar, ZTermMap  )
import Zeno.Type ( typeOf )
import Zeno.Context ( Context )

import qualified Zeno.Substitution as Substitution
import qualified Zeno.Context as Context
import qualified Zeno.Type as Type
import qualified Zeno.Term as Term
import qualified Zeno.Var as Var
import qualified Zeno.Evaluation as Eval

import qualified Control.Failure as Fail
import qualified Data.Set as Set
import qualified Data.Map as Map

maxDepth :: Int
maxDepth = 6

-- | Takes a term with free variables and returns a list of
-- possible values this term could take, by assigning values
-- to its free variables.
explore :: forall m . MonadUnique m => ZTerm -> m [ZTerm]
explore term =
  liftM nubOrd
    $ expl maxDepth term
  where
  -- Helper function for explore which takes a depth parameter
  -- starting at 'maxDepth' and decreasing with each unrolling.
  expl :: Int -> ZTerm -> m [ZTerm]
  
  -- Descend into the branches of a pattern match
  expl depth (Term.Cse _ cse_of cse_alts) = 
    concatMapM explAlt cse_alts
    where
    explAlt (Term.Alt alt_con alt_vars alt_term)
      | not (Term.isVar cse_of) = expl depth alt_term
      
      -- If we are pattern matching on a variable we update the value of
      -- that value down every branch with the pattern it was matched to.
      -- We then reverse this substitution on the returned values.
      | otherwise = do
        alt_term' <- Substitution.replace cse_of alt_pattern alt_term
        term_values <- expl depth alt_term'
        mapM (Substitution.replace alt_pattern cse_of) term_values
      where
      alt_pattern = Term.unflattenApp
        $ map Term.Var (alt_con : alt_vars)
        
  expl 0 term 
    | Term.isNormal term = return [term]
    | otherwise = return []
      
  expl depth term = do
    unrolled <- Context.unrollInnermost term
    expl (depth - 1) unrolled
      

guessContext :: (MonadUnique m, MonadFailure m) => ZTerm -> m Context
guessContext term = do
  potentials <- explore term
  Fail.when (null potentials)
  if allAlphaEq potentials
  then return (Context.new (const (head potentials)) empty)
  else do
    mby_cxt <- runMaybeT (matchContext potentials)
    maybe Fail.here return mby_cxt
  where
  allAlphaEq (a:as) = all (alphaEq a) as
  
  matchContext :: MonadUnique m => [ZTerm] -> MaybeT m Context
  matchContext terms = do
    Fail.unless (Var.isConstructorTerm fst_con)
    Fail.unless (all (== fst_con) other_cons)
    Fail.unless 
      $ assert (not $ null gap_idxs) 
      $ length gap_idxs == 1
    matched_gaps <- runMaybeT (matchContext gaps)
    return 
      $ maybe this_cxt (Context.compose this_cxt) matched_gaps 
    where
    flattened = map Term.flattenApp terms
    (fst_con:other_cons) = map head flattened
    
    args :: [[ZTerm]]
    args = map tail flattened
    paired_args = transpose args
    
    gap_idxs = findIndices (not . allAlphaEq) paired_args
    [gap_idx] = gap_idxs
    gaps = map (!! gap_idx) args
    gap_type = typeOf (head args !! gap_idx)
    
    this_cxt = Context.new (outerContext gap_idx) gap_type 

    outerContext gap_i fill = 
      Term.unflattenApp 
      $ fst_con : (setAt gap_i fill (head args))

