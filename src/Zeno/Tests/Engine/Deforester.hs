module Zeno.Tests.Engine.Deforester (
  tests
) where

import Prelude ()
import Zeno.Prelude
import Zeno.Core ( Zeno )
import Zeno.Var ( ZTerm )
import Zeno.Engine.Deforester ( simplify )

import qualified Control.Failure as Fail
import qualified Zeno.Term as Term
import qualified Zeno.Testing as Test

tests = Test.label "Deforester"
  $ Test.list 
  [ test_deforestSimple
  , test_deforestHOF
  , test_valueFactoring
  , test_patternFactoring
  ]
  
assertSimpEq :: ZTerm -> ZTerm -> Zeno Test.Test
assertSimpEq t1 t2 = do
  t1' <- simplify t1
  t2' <- simplify t2
  return
    $ Test.assertAlphaEq t1' t2'


-- | Test some simple deforestations
test_deforestSimple = 
  Test.label "Deforesting revapp"
    $ Test.run $ do
  Test.loadPrelude
  Test.newVar "xs" "list"
  Test.newVar "n" "nat"
  Test.newVar "f" "list->list"
  
  -- We will simplify "rev (xs ++ [n])",
  -- aiming for "n :: (rev xs)"
  rev_app <- Test.term "rev (app xs (cons n nil))"
  desired_form <- Test.term "cons n (rev xs)"
  
  assertSimpEq rev_app desired_form
    
    
-- | Simplify some higher-order functions
test_deforestHOF =
  Test.label "Deforesting HOF" 
    $ Test.run $ do
  Test.loadPrelude
  
  Test.newVar "xs" "list"
  Test.newVar "f" "nat -> nat"
  Test.newVar "g" "nat -> nat"
  
  mapmap1 <- Test.term "map f (map g xs)"
  mapmap2 <- Test.term "map (fun (x:nat) -> f (g x)) xs"
  
  assertSimpEq mapmap1 mapmap2
  
  
-- | Test simplifications which require value factoring
-- "rev (rev xs)" == "xs"
-- "len (rev xs)" == "len xs"
test_valueFactoring =
  Test.label "Value factoring"
    $ Test.run $ do
  Test.loadPrelude
  var_xs <- Test.newVar "xs" "list"
  
  revrev <- Test.term "rev (rev xs)"
  test1 <- assertSimpEq revrev (Term.Var var_xs)
  
  lenrev <- Test.term "len (rev xs)"
  len <- Test.term "len xs"
  test2 <- assertSimpEq lenrev len
  
  return
    $ Test.list [test1, test2]
    
  
-- | Test simplifications which require pattern factoring
-- "count n (xs ++ [m])" == "case n == m of { ... }"
-- "count n (rev xs)" == "count n xs"
test_patternFactoring =
  Test.label "Pattern factoring"
    $ Test.run $ do
  Test.loadPrelude
  
  Test.newVar "n" "nat"
  Test.newVar "m" "nat"
  Test.newVar "xs" "list"
  
  count_app <- Test.term "count n (app xs (cons m nil))"
  count_app2 <- Test.term count_app2_def
  test1 <- assertSimpEq count_app count_app2
  
  count <- Test.term "count n xs"
  count_rev <- Test.term "count n (rev xs)"
  test2 <- assertSimpEq count_rev count

  return
    $ Test.list [test1, test2]
  where
  count_app2_def = unlines $
    [ "case (eq n m) of "
    , "    true -> succ (count n xs)"
    , "  | false -> count n xs" ]
  
