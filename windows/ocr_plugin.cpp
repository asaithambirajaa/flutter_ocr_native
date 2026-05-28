#include "include/flutter_ocr_native/flutter_ocr_native_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include <gdiplus.h>
#include <shlobj.h>

#include <fstream>
#include <memory>
#include <regex>
#include <string>
#include <vector>

#pragma comment(lib, "gdiplus.lib")

namespace imaging = winrt::Windows::Graphics::Imaging;
namespace ocr = winrt::Windows::Media::Ocr;
namespace streams = winrt::Windows::Storage::Streams;

namespace {

class FlutterOcrNativePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterOcrNativePlugin();
  virtual ~FlutterOcrNativePlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void RecognizeFromPath(
      const std::string& path,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void RecognizeFromBytes(
      const std::vector<uint8_t>& bytes,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void BurnWatermark(
      const std::vector<uint8_t>& bytes,
      const flutter::EncodableMap& lines,
      int quality,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void CompressImage(
      const std::vector<uint8_t>& bytes,
      int quality,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableMap ProcessOcrResult(const ocr::OcrResult& ocr_result,
                                          const std::vector<uint8_t>& image_bytes);

  std::vector<uint8_t> MaskAadhaarOnImage(const std::vector<uint8_t>& image_bytes,
                                           const ocr::OcrResult& ocr_result);

  std::vector<uint8_t> CompressToJpeg(const std::vector<uint8_t>& bytes, int quality);
  std::vector<uint8_t> DrawWatermark(const std::vector<uint8_t>& bytes,
                                      const flutter::EncodableMap& lines, int quality);

  bool IsEnglish(const std::wstring& text);
  bool IsPrinted(const ocr::OcrResult& ocr_result);

  ocr::OcrEngine ocr_engine_{nullptr};
  ULONG_PTR gdiplus_token_{0};
};

void FlutterOcrNativePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.flutter_ocr_native/text_recognition",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterOcrNativePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterOcrNativePlugin::FlutterOcrNativePlugin() {
  winrt::init_apartment();

  // Initialize GDI+
  Gdiplus::GdiplusStartupInput gdiplus_input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiplus_input, nullptr);

  // Create OCR engine for English
  ocr_engine_ = ocr::OcrEngine::TryCreateFromLanguage(
      winrt::Windows::Globalization::Language(L"en-US"));
  if (!ocr_engine_) {
    ocr_engine_ = ocr::OcrEngine::TryCreateFromUserProfileLanguages();
  }
}

FlutterOcrNativePlugin::~FlutterOcrNativePlugin() {
  if (gdiplus_token_) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
  }
}

void FlutterOcrNativePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());

  if (method == "recognizeFromPath") {
    if (!args) { result->Error("INVALID_ARG", "Arguments required"); return; }
    auto it = args->find(flutter::EncodableValue("imagePath"));
    if (it == args->end()) { result->Error("INVALID_ARG", "imagePath required"); return; }
    auto path = std::get<std::string>(it->second);
    RecognizeFromPath(path, std::move(result));
  } else if (method == "recognizeFromBytes") {
    if (!args) { result->Error("INVALID_ARG", "Arguments required"); return; }
    auto it = args->find(flutter::EncodableValue("bytes"));
    if (it == args->end()) { result->Error("INVALID_ARG", "bytes required"); return; }
    auto bytes = std::get<std::vector<uint8_t>>(it->second);
    RecognizeFromBytes(bytes, std::move(result));
  } else if (method == "burnWatermark") {
    if (!args) { result->Error("INVALID_ARG", "Arguments required"); return; }
    auto bytes_it = args->find(flutter::EncodableValue("imageBytes"));
    auto lines_it = args->find(flutter::EncodableValue("lines"));
    auto quality_it = args->find(flutter::EncodableValue("quality"));
    if (bytes_it == args->end() || lines_it == args->end()) {
      result->Error("INVALID_ARG", "imageBytes and lines required"); return;
    }
    auto bytes = std::get<std::vector<uint8_t>>(bytes_it->second);
    auto lines = std::get<flutter::EncodableMap>(lines_it->second);
    int quality = quality_it != args->end() ? std::get<int>(quality_it->second) : 90;
    BurnWatermark(bytes, lines, quality, std::move(result));
  } else if (method == "compressImage") {
    if (!args) { result->Error("INVALID_ARG", "Arguments required"); return; }
    auto bytes_it = args->find(flutter::EncodableValue("imageBytes"));
    auto quality_it = args->find(flutter::EncodableValue("quality"));
    if (bytes_it == args->end()) { result->Error("INVALID_ARG", "imageBytes required"); return; }
    auto bytes = std::get<std::vector<uint8_t>>(bytes_it->second);
    int quality = quality_it != args->end() ? std::get<int>(quality_it->second) : 80;
    CompressImage(bytes, quality, std::move(result));
  } else if (method == "dispose") {
    result->Success(flutter::EncodableValue());
  } else {
    result->NotImplemented();
  }
}

void FlutterOcrNativePlugin::RecognizeFromPath(
    const std::string& path,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Read file into bytes
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file.is_open()) {
    result->Error("INVALID_ARG", "Could not open file: " + path);
    return;
  }
  auto size = file.tellg();
  file.seekg(0);
  std::vector<uint8_t> bytes(size);
  file.read(reinterpret_cast<char*>(bytes.data()), size);
  file.close();

  RecognizeFromBytes(bytes, std::move(result));
}

void FlutterOcrNativePlugin::RecognizeFromBytes(
    const std::vector<uint8_t>& bytes,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!ocr_engine_) {
    result->Error("NOT_INITIALIZED", "OCR engine not available");
    return;
  }

  try {
    // Create SoftwareBitmap from bytes via InMemoryRandomAccessStream
    auto stream = streams::InMemoryRandomAccessStream();
    auto writer = streams::DataWriter(stream.GetOutputStreamAt(0));
    writer.WriteBytes(winrt::array_view<const uint8_t>(bytes));
    writer.StoreAsync().get();
    writer.FlushAsync().get();
    stream.Seek(0);

    auto decoder = imaging::BitmapDecoder::CreateAsync(stream).get();
    auto bitmap = decoder.GetSoftwareBitmapAsync().get();

    // Convert to BGRA8 if needed (OCR requires this)
    if (bitmap.BitmapPixelFormat() != imaging::BitmapPixelFormat::Bgra8 ||
        bitmap.BitmapAlphaMode() != imaging::BitmapAlphaMode::Premultiplied) {
      bitmap = imaging::SoftwareBitmap::Convert(bitmap, imaging::BitmapPixelFormat::Bgra8,
                                        imaging::BitmapAlphaMode::Premultiplied);
    }

    // Run OCR
    auto ocr_result = ocr_engine_.RecognizeAsync(bitmap).get();
    auto response = ProcessOcrResult(ocr_result, bytes);
    result->Success(flutter::EncodableValue(response));
  } catch (const winrt::hresult_error& e) {
    result->Error("RECOGNITION_FAILED", winrt::to_string(e.message()));
  } catch (const std::exception& e) {
    result->Error("RECOGNITION_FAILED", e.what());
  }
}

flutter::EncodableMap FlutterOcrNativePlugin::ProcessOcrResult(
    const ocr::OcrResult& ocr_result, const std::vector<uint8_t>& image_bytes) {
  std::string full_text;
  flutter::EncodableList blocks;
  std::regex english_pattern("[A-Za-z0-9]");

  for (const auto& line : ocr_result.Lines()) {
    std::string line_text;
    flutter::EncodableList elements;
    double total_confidence = 0;
    int word_count = 0;

    for (const auto& word : line.Words()) {
      auto text = winrt::to_string(word.Text());
      if (!std::regex_search(text, english_pattern)) continue;

      auto rect = word.BoundingRect();
      flutter::EncodableMap bbox;
      bbox[flutter::EncodableValue("left")] = flutter::EncodableValue((double)rect.X);
      bbox[flutter::EncodableValue("top")] = flutter::EncodableValue((double)rect.Y);
      bbox[flutter::EncodableValue("width")] = flutter::EncodableValue((double)rect.Width);
      bbox[flutter::EncodableValue("height")] = flutter::EncodableValue((double)rect.Height);

      flutter::EncodableMap element;
      element[flutter::EncodableValue("text")] = flutter::EncodableValue(text);
      element[flutter::EncodableValue("boundingBox")] = flutter::EncodableValue(bbox);
      element[flutter::EncodableValue("confidence")] = flutter::EncodableValue(0.9);

      elements.push_back(flutter::EncodableValue(element));
      if (!line_text.empty()) line_text += " ";
      line_text += text;
      total_confidence += 0.9;
      word_count++;
    }

    if (elements.empty()) continue;

    auto line_rect = line.Words().GetAt(0).BoundingRect();
    flutter::EncodableMap line_bbox;
    line_bbox[flutter::EncodableValue("left")] = flutter::EncodableValue((double)line_rect.X);
    line_bbox[flutter::EncodableValue("top")] = flutter::EncodableValue((double)line_rect.Y);
    line_bbox[flutter::EncodableValue("width")] = flutter::EncodableValue((double)line_rect.Width);
    line_bbox[flutter::EncodableValue("height")] = flutter::EncodableValue((double)line_rect.Height);

    double avg_conf = word_count > 0 ? total_confidence / word_count : 0.9;

    flutter::EncodableMap line_map;
    line_map[flutter::EncodableValue("text")] = flutter::EncodableValue(line_text);
    line_map[flutter::EncodableValue("boundingBox")] = flutter::EncodableValue(line_bbox);
    line_map[flutter::EncodableValue("confidence")] = flutter::EncodableValue(avg_conf);
    line_map[flutter::EncodableValue("elements")] = flutter::EncodableValue(elements);

    flutter::EncodableMap block;
    block[flutter::EncodableValue("text")] = flutter::EncodableValue(line_text);
    block[flutter::EncodableValue("boundingBox")] = flutter::EncodableValue(line_bbox);
    block[flutter::EncodableValue("recognizedLanguage")] = flutter::EncodableValue("en");
    block[flutter::EncodableValue("lines")] = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(line_map)});

    blocks.push_back(flutter::EncodableValue(block));
    if (!full_text.empty()) full_text += "\n";
    full_text += line_text;
  }

  // Mask Aadhaar on image
  auto masked_bytes = MaskAadhaarOnImage(image_bytes, ocr_result);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("text")] = flutter::EncodableValue(full_text);
  response[flutter::EncodableValue("blocks")] = flutter::EncodableValue(blocks);
  response[flutter::EncodableValue("isPrinted")] = flutter::EncodableValue(true);
  if (masked_bytes.empty()) {
    response[flutter::EncodableValue("maskedImageBytes")] = flutter::EncodableValue();
  } else {
    response[flutter::EncodableValue("maskedImageBytes")] = flutter::EncodableValue(masked_bytes);
  }
  return response;
}

std::vector<uint8_t> FlutterOcrNativePlugin::MaskAadhaarOnImage(
    const std::vector<uint8_t>& image_bytes, const ocr::OcrResult& ocr_result) {
  // Find Aadhaar pattern in OCR lines
  std::regex aadhaar_pattern("(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})");
  std::smatch match;

  struct MaskInfo {
    float x, y, width, height;
  };
  std::vector<MaskInfo> rects_to_mask;

  for (const auto& line : ocr_result.Lines()) {
    // Build line text and track word positions
    std::string line_text;
    struct WordInfo { std::string text; float x, y, w, h; };
    std::vector<WordInfo> words;

    for (const auto& word : line.Words()) {
      auto text = winrt::to_string(word.Text());
      auto rect = word.BoundingRect();
      words.push_back({text, (float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height});
      if (!line_text.empty()) line_text += " ";
      line_text += text;
    }

    if (!std::regex_search(line_text, match, aadhaar_pattern)) continue;

    std::string first4 = match[1].str();
    std::string second4 = match[2].str();

    // Find bounding boxes of first 2 digit groups
    for (const auto& w : words) {
      if (w.text == first4 || w.text == second4) {
        rects_to_mask.push_back({w.x, w.y, w.w, w.h});
      }
    }

    // If we couldn't find individual words, mask proportionally
    if (rects_to_mask.empty() && !words.empty()) {
      int match_start = (int)match.position(0);
      int last4_start = (int)match.position(3);
      float total_width = 0;
      float min_x = words[0].x, min_y = words[0].y, max_h = words[0].h;
      for (const auto& w : words) {
        total_width += w.w;
        if (w.h > max_h) max_h = w.h;
      }
      float char_width = total_width / (float)line_text.length();
      float mask_left = min_x + match_start * char_width;
      float mask_width = (last4_start - match_start) * char_width;
      rects_to_mask.push_back({mask_left, min_y, mask_width, max_h});
    }

    break; // Found Aadhaar, stop searching
  }

  if (rects_to_mask.empty()) return {};

  // Load image with GDI+ and draw black rectangles
  IStream* stream = nullptr;
  auto hglobal = GlobalAlloc(GMEM_MOVEABLE, image_bytes.size());
  auto ptr = GlobalLock(hglobal);
  memcpy(ptr, image_bytes.data(), image_bytes.size());
  GlobalUnlock(hglobal);
  CreateStreamOnHGlobal(hglobal, TRUE, &stream);

  auto* image = Gdiplus::Image::FromStream(stream);
  if (!image || image->GetLastStatus() != Gdiplus::Ok) {
    if (stream) stream->Release();
    return {};
  }

  int img_width = image->GetWidth();
  int img_height = image->GetHeight();

  auto* output = new Gdiplus::Bitmap(img_width, img_height, PixelFormat32bppARGB);
  Gdiplus::Graphics graphics(output);
  graphics.DrawImage(image, 0, 0, img_width, img_height);

  // Draw black rectangles over Aadhaar digits
  Gdiplus::SolidBrush black_brush(Gdiplus::Color(255, 0, 0, 0));
  for (const auto& r : rects_to_mask) {
    float pad_x = r.width * 0.05f;
    float pad_y = r.height * 0.1f;
    graphics.FillRectangle(&black_brush,
      r.x - pad_x, r.y - pad_y,
      r.width + pad_x * 2, r.height + pad_y * 2);
  }

  // Save as JPEG
  CLSID jpeg_clsid;
  CLSIDFromString(L"{557CF401-1A04-11D3-9A73-0000F81EF32E}", &jpeg_clsid);
  IStream* out_stream = nullptr;
  CreateStreamOnHGlobal(nullptr, TRUE, &out_stream);

  Gdiplus::EncoderParameters params;
  params.Count = 1;
  params.Parameter[0].Guid = Gdiplus::EncoderQuality;
  params.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
  params.Parameter[0].NumberOfValues = 1;
  ULONG q = 90;
  params.Parameter[0].Value = &q;
  output->Save(out_stream, &jpeg_clsid, &params);

  STATSTG stat;
  out_stream->Stat(&stat, STATFLAG_NONAME);
  ULONG out_size = (ULONG)stat.cbSize.QuadPart;
  std::vector<uint8_t> out_bytes(out_size);
  LARGE_INTEGER zero = {};
  out_stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  out_stream->Read(out_bytes.data(), out_size, &read);

  delete output;
  delete image;
  out_stream->Release();
  stream->Release();

  return out_bytes;
}

void FlutterOcrNativePlugin::BurnWatermark(
    const std::vector<uint8_t>& bytes,
    const flutter::EncodableMap& lines,
    int quality,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto output = DrawWatermark(bytes, lines, quality);
  if (output.empty()) {
    result->Error("WATERMARK_FAILED", "Could not burn watermark");
    return;
  }
  result->Success(flutter::EncodableValue(output));
}

void FlutterOcrNativePlugin::CompressImage(
    const std::vector<uint8_t>& bytes,
    int quality,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto output = CompressToJpeg(bytes, quality);
  if (output.empty()) {
    result->Success(flutter::EncodableValue(bytes));
    return;
  }
  result->Success(flutter::EncodableValue(output));
}

std::vector<uint8_t> FlutterOcrNativePlugin::DrawWatermark(
    const std::vector<uint8_t>& bytes,
    const flutter::EncodableMap& lines,
    int quality) {
  // Load image with GDI+
  IStream* stream = nullptr;
  auto hglobal = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  auto ptr = GlobalLock(hglobal);
  memcpy(ptr, bytes.data(), bytes.size());
  GlobalUnlock(hglobal);
  CreateStreamOnHGlobal(hglobal, TRUE, &stream);

  auto* image = Gdiplus::Image::FromStream(stream);
  if (!image || image->GetLastStatus() != Gdiplus::Ok) {
    if (stream) stream->Release();
    return {};
  }

  int img_width = image->GetWidth();
  int img_height = image->GetHeight();

  // Calculate watermark dimensions
  float font_size = (std::max)(img_width * 0.03f, 36.0f);
  float line_height = font_size * 1.5f;
  float pad_h = img_width * 0.02f;
  float pad_v = img_width * 0.015f;
  int wm_height = (int)(lines.size() * line_height + pad_v * 2);
  int total_height = img_height + wm_height;

  // Create output bitmap
  auto* output = new Gdiplus::Bitmap(img_width, total_height, PixelFormat32bppARGB);
  Gdiplus::Graphics graphics(output);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);

  // Draw original image
  graphics.DrawImage(image, 0, 0, img_width, img_height);

  // Draw watermark background
  Gdiplus::SolidBrush bg_brush(Gdiplus::Color(180, 0, 0, 0));
  graphics.FillRectangle(&bg_brush, 0, img_height, img_width, wm_height);

  // Draw text
  Gdiplus::FontFamily font_family(L"Arial");
  Gdiplus::Font font(&font_family, font_size, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::SolidBrush text_brush(Gdiplus::Color(204, 255, 255, 255));

  float y = (float)img_height + pad_v;
  for (const auto& entry : lines) {
    auto key = std::get<std::string>(entry.first);
    auto value = std::get<std::string>(entry.second);
    auto text = key + ": " + value;

    // Convert to wide string
    int wlen = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
    std::wstring wtext(wlen, 0);
    MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, &wtext[0], wlen);

    Gdiplus::PointF point(pad_h, y);
    graphics.DrawString(wtext.c_str(), -1, &font, point, &text_brush);
    y += line_height;
  }

  // Save to bytes
  CLSID encoder_clsid;
  if (quality < 100) {
    // JPEG
    CLSIDFromString(L"{557CF401-1A04-11D3-9A73-0000F81EF32E}", &encoder_clsid);
  } else {
    // PNG
    CLSIDFromString(L"{557CF406-1A04-11D3-9A73-0000F81EF32E}", &encoder_clsid);
  }

  IStream* out_stream = nullptr;
  CreateStreamOnHGlobal(nullptr, TRUE, &out_stream);

  if (quality < 100) {
    Gdiplus::EncoderParameters params;
    params.Count = 1;
    params.Parameter[0].Guid = Gdiplus::EncoderQuality;
    params.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
    params.Parameter[0].NumberOfValues = 1;
    ULONG q = (ULONG)quality;
    params.Parameter[0].Value = &q;
    output->Save(out_stream, &encoder_clsid, &params);
  } else {
    output->Save(out_stream, &encoder_clsid, nullptr);
  }

  // Read output stream
  STATSTG stat;
  out_stream->Stat(&stat, STATFLAG_NONAME);
  ULONG out_size = (ULONG)stat.cbSize.QuadPart;
  std::vector<uint8_t> out_bytes(out_size);
  LARGE_INTEGER zero = {};
  out_stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  out_stream->Read(out_bytes.data(), out_size, &read);

  delete output;
  delete image;
  out_stream->Release();
  stream->Release();

  return out_bytes;
}

std::vector<uint8_t> FlutterOcrNativePlugin::CompressToJpeg(
    const std::vector<uint8_t>& bytes, int quality) {
  IStream* stream = nullptr;
  auto hglobal = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  auto ptr = GlobalLock(hglobal);
  memcpy(ptr, bytes.data(), bytes.size());
  GlobalUnlock(hglobal);
  CreateStreamOnHGlobal(hglobal, TRUE, &stream);

  auto* image = Gdiplus::Image::FromStream(stream);
  if (!image || image->GetLastStatus() != Gdiplus::Ok) {
    if (stream) stream->Release();
    return {};
  }

  CLSID jpeg_clsid;
  CLSIDFromString(L"{557CF401-1A04-11D3-9A73-0000F81EF32E}", &jpeg_clsid);

  IStream* out_stream = nullptr;
  CreateStreamOnHGlobal(nullptr, TRUE, &out_stream);

  Gdiplus::EncoderParameters params;
  params.Count = 1;
  params.Parameter[0].Guid = Gdiplus::EncoderQuality;
  params.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
  params.Parameter[0].NumberOfValues = 1;
  ULONG q = (ULONG)quality;
  params.Parameter[0].Value = &q;
  image->Save(out_stream, &jpeg_clsid, &params);

  STATSTG stat;
  out_stream->Stat(&stat, STATFLAG_NONAME);
  ULONG out_size = (ULONG)stat.cbSize.QuadPart;
  std::vector<uint8_t> out_bytes(out_size);
  LARGE_INTEGER zero = {};
  out_stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  out_stream->Read(out_bytes.data(), out_size, &read);

  delete image;
  out_stream->Release();
  stream->Release();

  return out_bytes;
}

}  // namespace

void FlutterOcrNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterOcrNativePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
