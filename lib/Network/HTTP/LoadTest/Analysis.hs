{-# LANGUAGE BangPatterns, RecordWildCards #-}

module Network.HTTP.LoadTest.Analysis
    (
    -- * Result analysis
      Analysis(..)
    , Basic(..)
    , analyseBasic
    , analyseFull
    ) where

import Criterion.Analysis (SampleAnalysis, analyseSample, scale)
import Network.HTTP.LoadTest.Types (Analysis(..), Basic(..), Summary(..),
                                    summEnd)
import Prelude hiding (catch)
import Statistics.Quantile (weightedAvg)
import qualified Data.Vector as V
import qualified Data.Vector.Generic as G
import qualified Data.Vector.Unboxed as U
import qualified Statistics.Sample as S

analyseFull :: V.Vector Summary -> IO (Analysis SampleAnalysis)
analyseFull sumv = do
  let start = summStart . G.head $ sumv
      end = summEnd . G.last $ sumv
      elapsed = end - start
      timeSlice = min elapsed 1 / 200
      slices = U.unfoldrN (round (elapsed / timeSlice)) go (sumv,1)
        where go (v,i) = let (a,b) = G.span (\s -> summStart s <= t) v
                             t = start + (i * timeSlice)
                         in Just (fromIntegral $ G.length a,(b,i+1))
      ci = 0.95
      resamples = 10 * 1000
  l <- analyseSample ci (G.convert . G.map summElapsed $ sumv) resamples
  t <- analyseSample ci slices resamples
  return Analysis {
                 latency = l
               , latency99 = weightedAvg 99 100 . G.map summElapsed $ sumv
               , latency999 = weightedAvg 999 1000 . G.map summElapsed $ sumv
               , latValues = sumv
               , throughput = scale (recip timeSlice) t
               , throughput10 = (/ timeSlice) . weightedAvg 10 100 $ slices
               , thrValues = slices
    }

analyseBasic :: V.Vector Summary -> Analysis Basic
analyseBasic sumv = Analysis {
                      latency = Basic {
                                  mean = S.mean . G.map summElapsed $ sumv
                                , stdDev = S.stdDev . G.map summElapsed $ sumv
                                }
                    , latency99 = weightedAvg 99 100 . G.map summElapsed $ sumv
                    , latency999 = weightedAvg 999 1000 . G.map summElapsed $ sumv
                    , latValues = sumv
                    , throughput = Basic {
                                     mean = S.mean slices / timeSlice
                                   , stdDev = S.stdDev slices / timeSlice
                                   }
                    , throughput10 = (/ timeSlice) . weightedAvg 10 100 $ slices
                    , thrValues = slices
                    }
 where start = summStart . G.head $ sumv
       end = summEnd . G.last $ sumv
       elapsed = end - start
       timeSlice = min elapsed 1 / 200
       slices = U.unfoldrN (round (elapsed / timeSlice)) go (sumv,1)
         where go (v,i) = let (a,b) = G.span (\s -> summStart s <= t) v
                              t = start + (i * timeSlice)
                          in Just (fromIntegral $ G.length a,(b,i+1))
