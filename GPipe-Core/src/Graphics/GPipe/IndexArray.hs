{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, ScopedTypeVariables #-}
module Graphics.GPipe.IndexArray (
    IndexArray(..), 
    IndexFormat(),
    newIndexArray,
    Graphics.GPipe.IndexArray.take,
    Graphics.GPipe.IndexArray.drop
) where

import Graphics.GPipe.Buffer
import Graphics.GPipe.Frame
import Prelude hiding (length)
import Control.Arrow (arr)

class BufferFormat a => IndexFormat a where
    indexToInt :: a -> HostFormat a -> Int
    glType :: a -> Int
        
instance IndexFormat BWord32 where
    indexToInt _ = fromIntegral  
    glType _ = glINT
instance IndexFormat BWord16 where
    indexToInt _ = fromIntegral  
    glType _ = glSHORT
instance IndexFormat BWord8 where
    indexToInt _ = fromIntegral    
    glType _ = glBYTE
    
data IndexArray = IndexArray { iArrName :: Int, length:: Int, offset:: Int, restart:: Maybe Int, indexType :: Int } 
newIndexArray :: forall os f a. IndexFormat a => Frame os f (Buffer os a, Maybe (HostFormat a)) IndexArray
newIndexArray = arr (\(buf, r) ->
        let a = undefined :: a in IndexArray (bufName buf) (bufElementCount buf) 0 (fmap (indexToInt a) r) (glType a)) 
 
take :: Int -> IndexArray -> IndexArray
take n i = i { length = min n (length i) }

drop :: Int -> IndexArray -> IndexArray
drop n i = i { length = max (l - n) 0, offset = offset i + n } where l = length i
 
glINT :: Int
glINT = undefined
glSHORT :: Int
glSHORT = undefined
glBYTE :: Int
glBYTE = undefined