package com.noaisu.loliSnatcher

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/** Decodes one sampled region at a time, without retaining a full-image bitmap. */
class ImageRegions {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            var decoder: BitmapRegionDecoder? = null
            var bitmap: Bitmap? = null
            try {
                val path = requireNotNull(call.argument<String>("path"))
                val file = File(path)
                require(file.length() in 1..64L * 1024 * 1024)
                // Region coordinates are encoded-image coordinates. Let the
                // normal bounded codec apply EXIF transforms rather than showing
                // a rotated/mirrored source incorrectly in the tile viewer.
                val orientation = try {
                    ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                } catch (_: Exception) {
                    ExifInterface.ORIENTATION_NORMAL
                }
                require(orientation == ExifInterface.ORIENTATION_NORMAL || orientation == ExifInterface.ORIENTATION_UNDEFINED)
                decoder = BitmapRegionDecoder.newInstance(path, false)
                val source = requireNotNull(decoder)
                require(source.width in 1..200000 && source.height in 1..200000)
                require(source.width.toLong() * source.height <= 512_000_000L)

                if (call.method == "getImageRegionInfo") {
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
                    val outputWidth = (right - left + sample - 1) / sample
                    val outputHeight = (bottom - top + sample - 1) / sample
                    require(outputWidth <= 1024 && outputHeight <= 1024)
                    val options = BitmapFactory.Options().apply {
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                        inSampleSize = sample
                    }
                    bitmap = source.decodeRegion(Rect(left, top, right, bottom), options)
                    val region = requireNotNull(bitmap)
                    require(region.width <= 1024 && region.height <= 1024)
                    val bytes = ByteArrayOutputStream().use { stream ->
                        check(region.compress(Bitmap.CompressFormat.PNG, 100, stream))
                        stream.toByteArray()
                    }
                    main.post { result.success(bytes) }
                }
            } catch (error: OutOfMemoryError) {
                // Best effort for Java allocation failures; prevention above is the primary safeguard.
                main.post { result.error("IMAGE_MEMORY_LIMIT", "Image region exceeds available memory", null) }
            } catch (error: Exception) {
                // Unsupported formats are a normal outcome of the metadata probe.
                if (call.method == "getImageRegionInfo") {
                    main.post { result.success(null) }
                } else {
                    main.post { result.error("IMAGE_REGION_ERROR", "Unable to decode image region", null) }
                }
            } finally {
                bitmap?.recycle()
                decoder?.recycle()
            }
        }
    }

    fun close() {
        executor.shutdown()
    }
}
