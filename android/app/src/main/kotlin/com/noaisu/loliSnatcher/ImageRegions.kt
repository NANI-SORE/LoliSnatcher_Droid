package com.noaisu.loliSnatcher

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.media.ExifInterface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Trace
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/** One worker and at most one retained source, accounted for by the Dart owner. */
class ImageRegions {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var retainedPath: String? = null
    private var retainedDecoder: BitmapRegionDecoder? = null

    private fun release(path: String? = retainedPath) {
        if (path != retainedPath) return
        retainedDecoder?.recycle()
        retainedDecoder = null
        retainedPath = null
    }

    private fun open(path: String): BitmapRegionDecoder {
        require(File(path).length() in 1..64L * 1024 * 1024)
        // Coordinates are encoded-image coordinates; transformed EXIF sources
        // remain on the ordinary bounded codec path.
        val orientation = try {
            ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        require(orientation == ExifInterface.ORIENTATION_NORMAL || orientation == ExifInterface.ORIENTATION_UNDEFINED)
        val decoder = requireNotNull(BitmapRegionDecoder.newInstance(path, false))
        try {
            require(decoder.width in 1..200000 && decoder.height in 1..200000)
            require(decoder.width.toLong() * decoder.height <= 512_000_000L)
            return decoder
        } catch (error: Throwable) {
            decoder.recycle()
            throw error
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            var temporary: BitmapRegionDecoder? = null
            var bitmap: Bitmap? = null
            try {
                val path = requireNotNull(call.argument<String>("path"))
                if (call.method == "releaseImageRegionDecoder") {
                    release(path)
                    main.post { result.success(null) }
                    return@execute
                }
                val metadata = call.method == "getImageRegionInfo"
                val retain = !metadata && call.argument<Boolean>("retainDecoder") == true
                Trace.beginSection("ImageRegions.open")
                val source = try {
                    if (!metadata && path == retainedPath) {
                        requireNotNull(retainedDecoder)
                    } else {
                        val opened = open(path)
                        temporary = opened
                        if (retain) {
                            // The bridge closes the old session before reserving its replacement.
                            check(retainedDecoder == null)
                            retainedDecoder = opened
                            retainedPath = path
                            temporary = null
                        }
                        opened
                    }
                } finally {
                    Trace.endSection()
                }
                if (metadata) {
                    val info = mapOf("width" to source.width, "height" to source.height)
                    main.post { result.success(info) }
                } else {
                    val left = requireNotNull(call.argument<Int>("left"))
                    val top = requireNotNull(call.argument<Int>("top"))
                    val right = requireNotNull(call.argument<Int>("right"))
                    val bottom = requireNotNull(call.argument<Int>("bottom"))
                    val sample = requireNotNull(call.argument<Int>("sampleSize"))
                    require(left >= 0 && top >= 0 && right <= source.width && bottom <= source.height)
                    require(right > left && bottom > top)
                    require(sample in 1..262144 && (sample and (sample - 1)) == 0)
                    require((right - left + sample - 1) / sample <= 1024)
                    require((bottom - top + sample - 1) / sample <= 1024)
                    val options = BitmapFactory.Options().apply {
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                        inSampleSize = sample
                        // Preserve the source color space. Only actual sRGB results
                        // use Flutter's raw descriptor (which implies sRGB).
                    }
                    Trace.beginSection("ImageRegions.decode")
                    try {
                        bitmap = source.decodeRegion(Rect(left, top, right, bottom), options)
                    } finally {
                        Trace.endSection()
                    }
                    val region = requireNotNull(bitmap)
                    require(region.width in 1..1024 && region.height in 1..1024)
                    require(region.allocationByteCount <= 16 * 1024 * 1024)
                    val raw = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        region.config == Bitmap.Config.ARGB_8888 &&
                        region.colorSpace?.isSrgb == true &&
                        (!region.hasAlpha() || region.isPremultiplied) &&
                        ByteOrder.nativeOrder() == ByteOrder.LITTLE_ENDIAN
                    Trace.beginSection(if (raw) "ImageRegions.rawCopy" else "ImageRegions.png")
                    val response = try {
                        if (raw) {
                            val count = region.rowBytes.toLong() * region.height
                            require(count in 1..8L * 1024 * 1024)
                            val bytes = ByteArray(count.toInt())
                            region.copyPixelsToBuffer(ByteBuffer.wrap(bytes))
                            mapOf("width" to region.width, "height" to region.height,
                                "rowBytes" to region.rowBytes, "format" to "rgba8888", "bytes" to bytes)
                        } else {
                            // Fixed-capacity staging avoids ByteArrayOutputStream's
                            // geometric growth and bounds unusual encoder output.
                            val bytes = BoundedOutputStream(16 * 1024 * 1024).use { stream ->
                                check(region.compress(Bitmap.CompressFormat.PNG, 100, stream))
                                stream.toByteArray()
                            }
                            mapOf("width" to region.width, "height" to region.height,
                                "format" to "png", "bytes" to bytes)
                        }
                    } finally {
                        Trace.endSection()
                    }
                    main.post { result.success(response) }
                }
            } catch (error: OutOfMemoryError) {
                main.post { result.error("IMAGE_MEMORY_LIMIT", "Image region exceeds available memory", null) }
            } catch (error: Exception) {
                if (call.method == "getImageRegionInfo") {
                    main.post { result.success(null) }
                } else {
                    main.post { result.error("IMAGE_REGION_ERROR", "Unable to decode image region", null) }
                }
            } finally {
                bitmap?.recycle()
                temporary?.recycle()
            }
        }
    }

    fun close() {
        executor.execute { release() }
        executor.shutdown()
    }

    private class BoundedOutputStream(private val limit: Int) : ByteArrayOutputStream(limit) {
        override fun write(value: Int) {
            require(count < limit)
            super.write(value)
        }
        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            require(length >= 0 && length <= limit - count)
            super.write(bytes, offset, length)
        }
    }
}
