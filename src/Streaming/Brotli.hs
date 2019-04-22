{-# LANGUAGE LambdaCase  #-}
{-# LANGUAGE Trustworthy #-}

-- |
-- Module      : Streaming.Brotli
-- Copyright   : © 2019 Herbert Valerio Riedel
--
-- Maintainer  : hvr@gnu.org
--
-- Compression and decompression of data streams in the \"Brotli\" format (<https://tools.ietf.org/html/rfc7932 RFC7932>)
--
module Streaming.Brotli
    ( -- * Simple interface
      compress
    , decompress
    , decompress_

      -- * Extended interface
      -- ** Compression
    , compressWith

    , Brotli.defaultCompressParams
    , Brotli.CompressParams
    , Brotli.compressLevel
    , Brotli.compressWindowSize
    , Brotli.compressMode
    , Brotli.compressSizeHint
    , Brotli.CompressionLevel(..)
    , Brotli.CompressionWindowSize(..)
    , Brotli.CompressionMode(..)

      -- ** Decompression
    , decompressWith

    , Brotli.defaultDecompressParams
    , Brotli.DecompressParams
    , Brotli.decompressDisableRingBufferReallocation
    ) where

import qualified Codec.Compression.Brotli  as Brotli
import           Control.Exception         (throwIO)
import qualified Data.ByteString           as B
import           Data.ByteString.Streaming (ByteString, chunk, effects,
                                            nextChunk, null_)
import           Streaming                 (MonadIO (liftIO), lift)

-- | Decompress a compressed Brotli stream.
--
-- The monadic return value is a stream representing the possibly
-- unconsumed leftover data from the input stream; see also 'decompress_'.
decompress :: MonadIO m
           => ByteString m r -- ^ compressed stream
           -> ByteString m (ByteString m r) -- ^ uncompressed stream
decompress = decompressWith Brotli.defaultDecompressParams

-- | Convenience wrapper around 'decompress' which fails eagerly if
-- the compressed stream contains any trailing data
decompress_ :: MonadIO m
            => ByteString m r -- ^ compressed stream
            -> ByteString m r -- ^ uncompressed stream
decompress_ is = do
   mr <- decompress is
   lift $ do
      noLeftovers <- null_ mr
      if noLeftovers
       then effects mr
       else liftIO (throwIO (Brotli.BrotliException "extra trailing data"))

-- | Like 'decompress' but with the ability to specify various decompression
-- parameters. Typical usage:
--
-- > decompressWith defaultDecompressParams { decompress... = ... }
decompressWith :: MonadIO m
               => Brotli.DecompressParams
               -> ByteString m r -- ^ compressed stream
               -> ByteString m (ByteString m r) -- ^ uncompressed stream
decompressWith params stream0 =
    go stream0 =<< liftIO (Brotli.decompressIO params)
  where
    go stream enc@(Brotli.DecompressInputRequired cont) = do
        lift (nextChunk stream) >>= \case
            Right (ibs,stream')
               | B.null ibs -> go stream' enc -- should not happen
               | otherwise  -> go stream' =<< liftIO (cont ibs)
            Left r          -> go (pure r) =<< liftIO (cont B.empty)
    go stream (Brotli.DecompressOutputAvailable obs cont) = do
        chunk obs
        go stream =<< liftIO cont
    go stream (Brotli.DecompressStreamEnd leftover) =
        pure (chunk leftover >> stream)
    go _stream (Brotli.DecompressStreamError ecode) =
        liftIO (throwIO ecode)

-- | Compress into a Brotli compressed stream.
compress :: MonadIO m
         => ByteString m r -- ^ compressed stream
         -> ByteString m r -- ^ uncompressed stream
compress = compressWith Brotli.defaultCompressParams

-- | Like 'compress' but with the ability to specify various compression
-- parameters. Typical usage:
--
-- > compressWith defaultCompressParams { compress... = ... }
compressWith :: MonadIO m
             => Brotli.CompressParams
             -> ByteString m r -- ^ uncompressed stream
             -> ByteString m r -- ^ compressed stream
compressWith params stream0 =
    go stream0 =<< liftIO (Brotli.compressIO params)
  where
    go stream enc@(Brotli.CompressInputRequired _flush cont) = do
        lift (nextChunk stream) >>= \case
          Right (x, stream')
            | B.null x  -> go stream' enc -- should not happen
            | otherwise -> go stream' =<< liftIO (cont x)
          Left r        -> go (pure r) =<< liftIO (cont B.empty)
    go stream (Brotli.CompressOutputAvailable obs cont) = do
        chunk obs
        go stream =<< liftIO cont
    go stream Brotli.CompressStreamEnd = stream
