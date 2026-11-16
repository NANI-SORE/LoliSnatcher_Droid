package com.noaisu.loliSnatcher

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import android.webkit.MimeTypeMap
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest

/** Application-context SAF publication; no Activity or in-memory byte array. */
class DownloadPublisher(private val context: Context) {
    private val resolver = context.contentResolver
    private fun directory(args: Map<*, *>): Uri {
        val destination = args["destination"] as Map<*, *>
        val tree = Uri.parse(destination["path"] as String)
        return DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    }
    private fun find(parent: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(parent, DocumentsContract.getDocumentId(parent))
        resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) return DocumentsContract.buildDocumentUriUsingTree(parent, cursor.getString(0))
            }
        }
        return null
    }
    fun exists(args: Map<*, *>): Boolean {
        val uri = find(directory(args), args["filename"] as String) ?: return false
        resolver.openFileDescriptor(uri, "r")?.use { if (it.statSize >= 0) return it.statSize > 0 }
        resolver.openInputStream(uri)?.use { return it.read() != -1 }
        return false
    }
    private fun digest(input: InputStream): String {
        val sha = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        input.use {
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                sha.update(buffer, 0, count)
            }
        }
        return sha.digest().joinToString("") { "%02x".format(it) }
    }
    private fun matches(uri: Uri, expected: String): Boolean = try {
        resolver.openInputStream(uri)?.let { digest(it) == expected } ?: false
    } catch (_: Exception) { false }

    fun publish(args: Map<*, *>): Map<String, Any> {
        val id = args["id"] as String
        require(id.matches(Regex("[a-zA-Z0-9-]+")))
        val parent = directory(args)
        val name = args["filename"] as String
        require(name == File(name).name && name.isNotBlank())
        val expected = args["digest"] as String
        val partial = File(args["partial"] as String)
        require(partial.canonicalPath.startsWith(File(DownloadHost.root(context), "staging").canonicalPath + File.separator))
        val file = AtomicFile(File(DownloadHost.root(context), "saf-$id.json"))
        var journal = if (file.baseFile.exists()) JSONObject(file.readFully().toString(Charsets.UTF_8)) else JSONObject()
        // A redownload has a new content digest or an explicitly reset Dart
        // journal. The old result remains on disk until replacement succeeds.
        val publicationId = args["publicationId"] as String
        if (journal.optString("digest") != expected || journal.optString("publicationId") != publicationId) journal = JSONObject()
        fun save() {
            val stream = file.startWrite()
            try {
                stream.write(journal.toString().toByteArray(Charsets.UTF_8))
                file.finishWrite(stream)
            } catch (error: Exception) { file.failWrite(stream); throw error }
        }
        fun copy(target: Uri, source: File) {
            resolver.openFileDescriptor(target, "rwt")?.use { descriptor ->
                FileInputStream(source).use { input ->
                    FileOutputStream(descriptor.fileDescriptor).use { output ->
                        input.copyTo(output, 64 * 1024)
                        output.flush()
                        // Cloud providers may return a pipe, which cannot be
                        // fsynced. Their close plus read-back verification is
                        // the publication boundary; regular files also fsync.
                        if (OsConstants.S_ISREG(Os.fstat(descriptor.fileDescriptor).st_mode)) descriptor.fileDescriptor.sync()
                    }
                }
            } ?: error("storage")
        }
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(File(name).extension.lowercase()) ?: "application/octet-stream"
        if (!journal.has("digest")) {
            val old = find(parent, name)
            if (old != null && args["overwrite"] != true) error("publicationAmbiguous")
            journal.put("digest", expected)
            journal.put("publicationId", publicationId)
            journal.put("old", old?.toString())
            save()
        }
        if (!journal.has("result")) {
            if (journal.optBoolean("renaming")) {
                val recovered = find(parent, name)
                if (recovered != null && matches(recovered, expected)) {
                    journal.put("result", recovered.toString())
                    save()
                }
            }
        }
        if (!journal.has("result")) {
            val temporaryName = ".$name.$id.part"
            val temporary: Uri
            if (journal.has("temporary")) temporary = Uri.parse(journal.getString("temporary"))
            else {
                val recovered = find(parent, temporaryName)
                if (recovered == null && journal.optBoolean("creatingTemporary")) error("publicationAmbiguous")
                journal.put("creatingTemporary", true)
                save()
                temporary = recovered ?: DocumentsContract.createDocument(resolver, parent, mime, temporaryName) ?: error("storage")
            }
            journal.put("temporary", temporary.toString())
            save()
            if (!matches(temporary, expected)) {
                copy(temporary, partial)
                check(matches(temporary, expected)) { "validation" }
            }
            // Record intent before the potentially non-atomic provider rename.
            journal.put("renaming", true)
            save()
            val renamed = try { DocumentsContract.renameDocument(resolver, temporary, name) } catch (_: Exception) { null }
            if (renamed != null) {
                journal.put("result", renamed.toString())
            } else {
                // Providers without rename get a separate final copy. The
                // previous complete document survives until verification.
                if (journal.optBoolean("creatingFinal") && !journal.has("finalCopy")) {
                    error("publicationAmbiguous")
                }
                journal.put("creatingFinal", true)
                save()
                val finalCopy = if (journal.has("finalCopy")) Uri.parse(journal.getString("finalCopy"))
                    else DocumentsContract.createDocument(resolver, parent, mime, name) ?: error("storage")
                journal.put("finalCopy", finalCopy.toString())
                save()
                copy(finalCopy, partial)
                check(matches(finalCopy, expected)) { "publicationAmbiguous" }
                journal.put("result", finalCopy.toString())
                try { DocumentsContract.deleteDocument(resolver, temporary) } catch (_: Exception) {}
            }
            save()
        }
        val result = Uri.parse(journal.getString("result"))
        check(matches(result, expected)) { "publicationAmbiguous" }
        var actualName = name
        resolver.query(result, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) actualName = it.getString(0)
        }
        if (args["writeJson"] == true && !journal.optBoolean("sidecarDone")) {
            val sidecarName = actualName.substringBeforeLast('.', actualName) + ".json"
            val sidecar = if (journal.has("sidecar")) Uri.parse(journal.getString("sidecar"))
                else find(parent, sidecarName) ?: DocumentsContract.createDocument(resolver, parent, "application/json", sidecarName) ?: error("storage")
            journal.put("sidecar", sidecar.toString())
            save()
            resolver.openOutputStream(sidecar, "wt")?.use {
                it.write(JSONObject(args["item"] as Map<*, *>).put("savedFileName", actualName).toString().toByteArray(Charsets.UTF_8))
                it.flush()
            } ?: error("storage")
            journal.put("sidecarDone", true)
            save()
        }
        val old = journal.optString("old")
        if (args["overwrite"] == true && old.isNotEmpty() && old != result.toString()) {
            try { DocumentsContract.deleteDocument(resolver, Uri.parse(old)) } catch (_: Exception) {}
        }
        return mapOf("destination" to result.toString(), "filename" to actualName,
            "warning" to if (actualName != name) "providerRenamed" else "")
    }
}
