{-# OPTIONS_GHC -fno-warn-orphans #-}

module Main(main) where

import           Streaming.Brotli

import qualified Data.ByteString           as BS
import qualified Data.ByteString.Streaming as S
import qualified Streaming                 as S
import qualified Streaming.Prelude         as PP

import           Test.QuickCheck           (Arbitrary (arbitrary), Property,
                                            counterexample, quickCheck,
                                            withMaxSuccess)
import           Test.QuickCheck.Monadic   (assert, monadicIO, monitor, run)

-- | roundtrip without trailing extra data
prop_roundTrip :: [BS.ByteString] -> Property
prop_roundTrip bss = monadicIO $ do
    bss' <- run $ pipeline bss
    monitor $ counterexample $ show bss'
    assert (BS.concat bss' == BS.concat bss)
  where
    pipeline :: S.MonadIO m => [BS.ByteString] -> m [BS.ByteString]
    pipeline = PP.toList_ . S.toChunks . decompress_ . compress . S.fromChunks . PP.each

-- | roundtrip with trailing extra data
prop_roundTrip2 :: [BS.ByteString] -> [BS.ByteString] -> Property
prop_roundTrip2 bss trailer = monadicIO $ do
    (bss',trailer') <- run $ pipeline (bss,trailer)
    monitor $ counterexample $ show (bss',trailer')
    assert ((BS.concat bss', BS.concat trailer') == (BS.concat bss, BS.concat trailer))
  where
    pipeline :: S.MonadIO m => ([BS.ByteString],[BS.ByteString]) -> m ([BS.ByteString],[BS.ByteString])
    pipeline (ibs,itl) = do
      let itls = S.fromChunks . PP.each $ itl
      obs PP.:> tbss <- PP.toList . S.toChunks . decompress . (`S.append` itls) . compress . S.fromChunks . PP.each $ ibs
      tbs <- PP.toList_ . S.toChunks $ tbss
      pure (obs,tbs)

main :: IO ()
main = do
  quickCheck (withMaxSuccess 10000 prop_roundTrip)
  quickCheck (withMaxSuccess 10000 prop_roundTrip2)

instance Arbitrary BS.ByteString where
    arbitrary = BS.pack <$> arbitrary
