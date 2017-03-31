{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Crypto.PVSS.DLEQ
    ( DLEQ(..)
    , Proof(..)
    , ParallelProof(..)
    , ParallelProofs(..)
    , Challenge
    , generate
    , verify
    , generateParallel
    , verifyParallel
    ) where

import           Control.DeepSeq
import           Crypto.PVSS.ECC
import           Data.Binary
import           Data.Binary.Get (getByteString)
import           Data.Binary.Put (putByteString)
import           Data.ByteString (ByteString)
import           GHC.Generics

data DLEQ = DLEQ
    { dleq_g1 :: !Point -- ^ g1 parameter
    , dleq_h1 :: !Point -- ^ h1 parameter where h1 = g1^a
    , dleq_g2 :: !Point -- ^ g2 parameter
    , dleq_h2 :: !Point -- ^ h2 parameter where h2 = g2^a
    } deriving (Show,Eq,Generic)

instance NFData DLEQ

newtype Challenge = Challenge ByteString
    deriving (Show,Eq,NFData)
instance Binary Challenge where
    put (Challenge c) = putByteString c
    get = Challenge <$> getByteString 32

-- | The generated proof
data Proof = Proof
    { proof_c :: !Challenge
    , proof_z :: !Scalar
    } deriving (Show,Eq,Generic)

instance Binary Proof
instance NFData Proof

newtype ParallelProof = ParallelProof { parallelProof_z :: Scalar }
    deriving (Show,Eq,Generic)

instance Binary ParallelProof
instance NFData ParallelProof

data ParallelProofs = ParallelProofs
    { parallelProofsChallenge :: !Challenge
    , parallelProofsValues    :: ![ParallelProof]
    } deriving (Show,Eq,Generic)

instance Binary ParallelProofs
instance NFData ParallelProofs

-- | Generate a proof
generate :: Scalar -- ^ random value
         -> Scalar -- ^ a
         -> DLEQ   -- ^ DLEQ parameters to generate from
         -> Proof
generate w a (DLEQ g1 h1 g2 h2) = Proof (Challenge c) r
  where
    a1     = g1 .* w
    a2     = g2 .* w
    c      = hashPoints [h1,h2,a1,a2]
    r      = w #+ (a #* keyFromBytes c)

-- | Verify a proof
verify :: DLEQ  -- ^ DLEQ parameter used to verify
       -> Proof -- ^ the proof to verify
       -> Bool
verify (DLEQ g1 h1 g2 h2) (Proof (Challenge ch) r) = ch == hashPoints [h1,h2,a1,a2]
  where
    r1 = g1 .* r
    r2 = g2 .* r
    c = keyFromBytes ch
    a1 = r1 .- (h1 .* c)
    a2 = r2 .- (h2 .* c)

-- | Generate all the proofs with a commonly computed challenge
generateParallel :: [(Scalar, Scalar, DLEQ)]     -- (random value w, secret a, DLEQ parameter)
                 -> ParallelProofs
generateParallel l =
    let as = map (\(r, _, (DLEQ g1 _ g2 _)) -> (g1 .* r, g2 .* r)) l
        h  =  concatMap (\(_, _, (DLEQ _ v1 _ v2)) -> [v1,v2]) l
           ++ concatMap (\(a1, a2) -> [a1,a2]) as
        -- all v1,a2 followed by all (a1,a2)
        challenge = hashPoints h
        c = keyFromBytes challenge

     in ParallelProofs
            { parallelProofsChallenge = Challenge challenge
            , parallelProofsValues    = map (\(w, a, _) -> ParallelProof (w #+ (a #* c))) l
            }

-- | verify proof with a commonly computed challenge
verifyParallel :: [DLEQ]
               -> ParallelProofs
               -> Bool
verifyParallel dleqs proofs =
    let computed = zipWith verifyOne dleqs (parallelProofsValues proofs)
     in ch == hashPoints (concatMap fst computed ++ concatMap snd computed)
  where
    (Challenge ch) = parallelProofsChallenge proofs
    verifyOne :: DLEQ -> ParallelProof -> ([Point], [Point])
    verifyOne (DLEQ g1 h1 g2 h2) (ParallelProof r) = ([h1,h2], [a1,a2])
      where
        r1 = g1 .* r
        r2 = g2 .* r
        c = keyFromBytes ch
        a1 = r1 .- (h1 .* c)
        a2 = r2 .- (h2 .* c)
