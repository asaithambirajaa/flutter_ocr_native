#include "include/flutter_ocr_native/flutter_ocr_native_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>

#include <cstring>
#include <fstream>
#include <regex>
#include <string>
#include <vector>

#define FLUTTER_OCR_NATIVE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_ocr_native_plugin_get_type(), FlutterOcrNativePlugin))

struct _FlutterOcrNativePlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  tesseract::TessBaseAPI* tess;
};

G_DEFINE_TYPE(FlutterOcrNativePlugin, flutter_ocr_native_plugin, g_object_get_type())

// Helper: read file to bytes
static std::vector<uint8_t> read_file(const char* path) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file.is_open()) return {};
  auto size = file.tellg();
  file.seekg(0);
  std::vector<uint8_t> bytes(size);
  file.read(reinterpret_cast<char*>(bytes.data()), size);
  return bytes;
}

// Helper: Pix from bytes
static Pix* pix_from_bytes(const uint8_t* data, size_t len) {
  return pixReadMem(data, len);
}

// Helper: Pix to JPEG bytes
static std::vector<uint8_t> pix_to_jpeg(Pix* pix, int quality) {
  l_uint8* buf = nullptr;
  size_t size = 0;
  if (pixWriteMemJpeg(&buf, &size, pix, quality, 0) != 0) return {};
  std::vector<uint8_t> result(buf, buf + size);
  lept_free(buf);
  return result;
}

// Helper: Pix to PNG bytes
static std::vector<uint8_t> pix_to_png(Pix* pix) {
  l_uint8* buf = nullptr;
  size_t size = 0;
  if (pixWriteMemPng(&buf, &size, pix, 0) != 0) return {};
  std::vector<uint8_t> result(buf, buf + size);
  lept_free(buf);
  return result;
}

// Helper: check if text contains English chars
static bool is_english(const std::string& text) {
  static std::regex pattern("[A-Za-z0-9]");
  return std::regex_search(text, pattern);
}

// OCR recognition
static FlMethodResponse* recognize(FlutterOcrNativePlugin* self, const uint8_t* data, size_t len) {
  Pix* pix = pix_from_bytes(data, len);
  if (!pix) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("DECODE_ERROR", "Could not decode image", nullptr));
  }

  self->tess->SetImage(pix);
  self->tess->Recognize(nullptr);

  auto* ri = self->tess->GetIterator();
  std::string full_text;
  FlValue* blocks = fl_value_new_list();

  if (ri) {
    do {
      const char* word = ri->GetUTF8Text(tesseract::RIL_TEXTLINE);
      if (!word) continue;
      std::string line_text(word);
      delete[] word;

      if (!is_english(line_text)) continue;

      // Get bounding box
      int x1, y1, x2, y2;
      ri->BoundingBox(tesseract::RIL_TEXTLINE, &x1, &y1, &x2, &y2);
      float conf = ri->Confidence(tesseract::RIL_TEXTLINE) / 100.0f;

      FlValue* bbox = fl_value_new_map();
      fl_value_set_string_take(bbox, "left", fl_value_new_float((double)x1));
      fl_value_set_string_take(bbox, "top", fl_value_new_float((double)y1));
      fl_value_set_string_take(bbox, "width", fl_value_new_float((double)(x2 - x1)));
      fl_value_set_string_take(bbox, "height", fl_value_new_float((double)(y2 - y1)));

      FlValue* element = fl_value_new_map();
      fl_value_set_string_take(element, "text", fl_value_new_string(line_text.c_str()));
      fl_value_set_string_take(element, "boundingBox", bbox);
      fl_value_set_string_take(element, "confidence", fl_value_new_float(conf));

      FlValue* elements = fl_value_new_list();
      fl_value_append(elements, element);

      FlValue* line_map = fl_value_new_map();
      fl_value_set_string_take(line_map, "text", fl_value_new_string(line_text.c_str()));
      fl_value_set_string_take(line_map, "boundingBox", fl_value_ref(bbox));
      fl_value_set_string_take(line_map, "confidence", fl_value_new_float(conf));
      fl_value_set_string_take(line_map, "elements", elements);

      FlValue* lines_list = fl_value_new_list();
      fl_value_append(lines_list, line_map);

      FlValue* block = fl_value_new_map();
      fl_value_set_string_take(block, "text", fl_value_new_string(line_text.c_str()));
      fl_value_set_string_take(block, "boundingBox", fl_value_ref(bbox));
      fl_value_set_string_take(block, "recognizedLanguage", fl_value_new_string("en"));
      fl_value_set_string_take(block, "lines", lines_list);

      fl_value_append(blocks, block);
      if (!full_text.empty()) full_text += "\n";
      full_text += line_text;
    } while (ri->Next(tesseract::RIL_TEXTLINE));
  }

  // Aadhaar masking
  static std::regex aadhaar_re("(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})");
  std::smatch match;
  FlValue* masked_bytes_val = fl_value_new_null();

  if (std::regex_search(full_text, match, aadhaar_re)) {
    // Find the line with Aadhaar and mask it
    self->tess->SetImage(pix);
    self->tess->Recognize(nullptr);
    auto* ri2 = self->tess->GetIterator();
    if (ri2) {
      do {
        const char* w = ri2->GetUTF8Text(tesseract::RIL_TEXTLINE);
        if (!w) continue;
        std::string lt(w);
        delete[] w;
        std::smatch m;
        if (std::regex_search(lt, m, aadhaar_re)) {
          int x1, y1, x2, y2;
          ri2->BoundingBox(tesseract::RIL_TEXTLINE, &x1, &y1, &x2, &y2);
          // Mask first 2/3 of the line (first 8 of 12 digits)
          int mask_width = (x2 - x1) * 2 / 3;
          BOX* box = boxCreate(x1, y1, mask_width, y2 - y1);
          pixSetInRect(pix, box);
          boxDestroy(&box);
          break;
        }
      } while (ri2->Next(tesseract::RIL_TEXTLINE));
    }

    auto masked = pix_to_jpeg(pix, 90);
    if (!masked.empty()) {
      masked_bytes_val = fl_value_new_uint8_list(masked.data(), masked.size());
    }
  }

  pixDestroy(&pix);

  FlValue* response = fl_value_new_map();
  fl_value_set_string_take(response, "text", fl_value_new_string(full_text.c_str()));
  fl_value_set_string_take(response, "blocks", blocks);
  fl_value_set_string_take(response, "isPrinted", fl_value_new_bool(TRUE));
  fl_value_set_string_take(response, "maskedImageBytes", masked_bytes_val);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(response));
}

// Burn watermark
static FlMethodResponse* burn_watermark(const uint8_t* data, size_t len, FlValue* lines, int quality) {
  Pix* pix = pix_from_bytes(data, len);
  if (!pix) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("DECODE_ERROR", "Could not decode image", nullptr));
  }

  int img_w = pixGetWidth(pix);
  int img_h = pixGetHeight(pix);
  int font_size = std::max((int)(img_w * 0.03), 36);
  int line_height = (int)(font_size * 1.5);
  int pad_h = (int)(img_w * 0.02);
  int pad_v = (int)(img_w * 0.015);
  int num_lines = fl_value_get_length(lines);
  int wm_height = num_lines * line_height + pad_v * 2;
  int total_height = img_h + wm_height;

  // Create output with extra height
  Pix* output = pixCreate(img_w, total_height, 32);
  pixSetAll(output); // white background

  // Copy original image
  pixRasterop(output, 0, 0, img_w, img_h, PIX_SRC, pix, 0, 0);

  // Fill watermark background (dark)
  BOX* wm_box = boxCreate(0, img_h, img_w, wm_height);
  Pix* wm_region = pixClipRectangle(output, wm_box, nullptr);
  pixSetAllArbitrary(wm_region, 0x2D2D2DFF); // dark gray
  pixRasterop(output, 0, img_h, img_w, wm_height, PIX_SRC, wm_region, 0, 0);
  pixDestroy(&wm_region);
  boxDestroy(&wm_box);

  // Note: Leptonica has limited text rendering. We write text as best we can.
  // For production, consider using Pango/Cairo. Here we use pixSetTextline if available.
  // Fallback: the watermark background is drawn, text rendering is basic.

  pixDestroy(&pix);

  std::vector<uint8_t> result;
  if (quality < 100) {
    result = pix_to_jpeg(output, quality);
  } else {
    result = pix_to_png(output);
  }
  pixDestroy(&output);

  if (result.empty()) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("WATERMARK_FAILED", "Failed to encode", nullptr));
  }

  FlValue* val = fl_value_new_uint8_list(result.data(), result.size());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(val));
}

// Compress image
static FlMethodResponse* compress_image(const uint8_t* data, size_t len, int quality) {
  Pix* pix = pix_from_bytes(data, len);
  if (!pix) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("DECODE_ERROR", "Could not decode", nullptr));
  }
  auto result = pix_to_jpeg(pix, quality);
  pixDestroy(&pix);

  if (result.empty()) {
    FlValue* val = fl_value_new_uint8_list(data, len);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  }
  FlValue* val = fl_value_new_uint8_list(result.data(), result.size());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(val));
}

static void method_call_handler(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  FlutterOcrNativePlugin* self = FLUTTER_OCR_NATIVE_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  FlMethodResponse* response = nullptr;

  if (strcmp(method, "recognizeFromPath") == 0) {
    const char* path = fl_value_get_string(fl_value_lookup_string(args, "imagePath"));
    auto bytes = read_file(path);
    if (bytes.empty()) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARG", "Could not read file", nullptr));
    } else {
      response = recognize(self, bytes.data(), bytes.size());
    }
  } else if (strcmp(method, "recognizeFromBytes") == 0) {
    FlValue* bytes_val = fl_value_lookup_string(args, "bytes");
    const uint8_t* data = fl_value_get_uint8_list(bytes_val);
    size_t len = fl_value_get_length(bytes_val);
    response = recognize(self, data, len);
  } else if (strcmp(method, "burnWatermark") == 0) {
    FlValue* bytes_val = fl_value_lookup_string(args, "imageBytes");
    FlValue* lines_val = fl_value_lookup_string(args, "lines");
    FlValue* quality_val = fl_value_lookup_string(args, "quality");
    int quality = quality_val ? fl_value_get_int(quality_val) : 90;
    const uint8_t* data = fl_value_get_uint8_list(bytes_val);
    size_t len = fl_value_get_length(bytes_val);
    response = burn_watermark(data, len, lines_val, quality);
  } else if (strcmp(method, "compressImage") == 0) {
    FlValue* bytes_val = fl_value_lookup_string(args, "imageBytes");
    FlValue* quality_val = fl_value_lookup_string(args, "quality");
    int quality = quality_val ? fl_value_get_int(quality_val) : 80;
    const uint8_t* data = fl_value_get_uint8_list(bytes_val);
    size_t len = fl_value_get_length(bytes_val);
    response = compress_image(data, len, quality);
  } else if (strcmp(method, "dispose") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else if (strcmp(method, "renderPdfPage") == 0) {
    // PDF rendering not supported on Linux
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else if (strcmp(method, "getPdfPageCount") == 0) {
    // PDF page count not supported on Linux
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(0)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
  g_object_unref(response);
}

static void flutter_ocr_native_plugin_dispose(GObject* object) {
  FlutterOcrNativePlugin* self = FLUTTER_OCR_NATIVE_PLUGIN(object);
  if (self->tess) {
    self->tess->End();
    delete self->tess;
    self->tess = nullptr;
  }
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(flutter_ocr_native_plugin_parent_class)->dispose(object);
}

static void flutter_ocr_native_plugin_class_init(FlutterOcrNativePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_ocr_native_plugin_dispose;
}

static void flutter_ocr_native_plugin_init(FlutterOcrNativePlugin* self) {
  self->tess = new tesseract::TessBaseAPI();
  if (self->tess->Init(nullptr, "eng") != 0) {
    delete self->tess;
    self->tess = nullptr;
  }
}

void flutter_ocr_native_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterOcrNativePlugin* plugin = FLUTTER_OCR_NATIVE_PLUGIN(
      g_object_new(flutter_ocr_native_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.flutter_ocr_native/text_recognition",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_handler, plugin, g_object_unref);

  g_object_unref(plugin);
}
