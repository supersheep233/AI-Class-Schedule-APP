import base64
import json
import os
import traceback
import asyncio
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import StreamingResponse
from openai import AsyncOpenAI

# Kimi (Moonshot AI) 配置
MOONSHOT_API_KEY = os.environ.get("MOONSHOT_API_KEY", "<YOUR_API_KEY>")
kimi_client = AsyncOpenAI(
    api_key=MOONSHOT_API_KEY,
    base_url="https://api.moonshot.cn/v1"
)
KIMI_MODEL = "kimi-k2.5"

app = FastAPI()


def encode_image_to_data_url(file_bytes: bytes, content_type: str) -> str:
    """将图片字节流转换为 data URL 格式，供视觉模型使用"""
    mime_type = content_type if content_type else "image/png"
    b64 = base64.b64encode(file_bytes).decode("utf-8")
    return f"data:{mime_type};base64,{b64}"


@app.post("/api/parse_schedule")
async def parse_schedule(file: UploadFile = File(...)):
    async def process_stream():
        try:
            # 0. 读取图片
            yield json.dumps({"status": "progress", "message": "正在读取图片..."}, ensure_ascii=False) + "\n"
            await asyncio.sleep(0.1)

            contents = await file.read()
            image_data_url = encode_image_to_data_url(contents, file.content_type or "image/png")

            # ============================================================
            # 阶段 1/2：调用 Kimi v2.5 视觉能力，将课表图片转为 Markdown 表格
            # ============================================================
            yield json.dumps({"status": "progress", "message": "阶段1/2: 正在使用 Kimi v2.5 识别课表图片..."}, ensure_ascii=False) + "\n"
            await asyncio.sleep(0.1)

            step1_prompt = (
                "请首先判断这张图片是否是包含课程信息的课程表或课表截图。"
                "如果它是自拍、风景图、普通聊天截图等非课程表图片，请直接且仅回复“ERROR: NOT_A_SCHEDULE”。\n"
                "如果确认是课程表，请仔细识别其中的全部内容。\n"
                "要求：1) 将主体的课程时间表识别并输出为一个 Markdown 表格，保留所有课程信息（课程名、教师、教室、周次等）；"
                "2) 如果图片中有节次对应的具体时间（如 第一节 8:00-8:50），请体现在表格或文字说明中；"
                "3) 课表下方或周围的其他备注文字、解释性文字也请一并提取出来，放在表格的下方。"
            )

            step1_response = await kimi_client.chat.completions.create(
                model=KIMI_MODEL,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "image_url", "image_url": {"url": image_data_url}},
                            {"type": "text", "text": step1_prompt},
                        ],
                    }
                ],
                extra_body={
                    "thinking": {"type": "disabled"}
                },  # 关闭思考
                stream=True,
            )

            markdown_table = ""
            async for chunk in step1_response:
                if chunk.choices and chunk.choices[0].delta.content:
                    delta = chunk.choices[0].delta.content
                    markdown_table += delta

                    # 实时拦截错误码：一旦模型判定不是课表，立刻终止并返回给前端错误信息
                    if "ERROR: NOT_A_SCHEDULE" in markdown_table:
                        yield json.dumps({"status": "error", "message": "上传错误：系统检测到该图片并非课程表，请上传正确的课表截图！"}, ensure_ascii=False) + "\n"
                        return

                    yield json.dumps({"status": "generating", "message": delta}, ensure_ascii=False) + "\n"
                    await asyncio.sleep(0.01)

            if not markdown_table.strip():
                yield json.dumps({"status": "error", "message": "阶段1失败：Kimi 未能识别出任何表格内容。"}, ensure_ascii=False) + "\n"
                return

            yield json.dumps({"status": "progress", "message": "阶段1完成！已提取 Markdown 表格，准备进行 JSON 转换..."}, ensure_ascii=False) + "\n"
            await asyncio.sleep(0.1)

            # ============================================================
            # 阶段 2/2：调用 Kimi v2.5 将 Markdown 表格整理为结构化 JSON
            # ============================================================
            yield json.dumps({"status": "progress", "message": "阶段2/2: 正在使用 Kimi v2.5 将表格转为结构化 JSON..."}, ensure_ascii=False) + "\n"
            await asyncio.sleep(0.1)

            step2_prompt = f"""
你是一个专业的高校教务系统数据提取专家。下面是经过初步识别的课程表内容（包含 Markdown 表格及可能的备注说明）：

<schedule_content>
{markdown_table}
</schedule_content>

请理解这段表格文本中的合并单元格和不规则表头，精确提取出所有课程及时间信息，提取为一个严格的 JSON 对象。

【提取规则】
1. 明确对应星期（dayOfWeek: 1-7）和具体的上课节次（startSlot 和 endSlot）。
2. 单元格内的格式若包含分隔符（如 "◇"、"|"、"@"、"·"），请注意拆分。
3. **拆分多门课程**：如果同一时间段内有不同的课程，**必须拆分为多个独立的 JSON 对象**。
4. **展平周次数组（极其重要）**：将周次描述转换为整数数组。
   - 例："1-10周" -> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
   - 例："5-12单周" -> [5, 7, 9, 11]
5. **排除人名误判**：带有"周"的文本不一定教师姓名，有可能是周次的周，请根据上下文的格式判断！
6. **提取具体时间（极其重要）**：如果表格中有节次对应的具体时间段（如 "8:00-8:50"），必须填入 timeSlots 数组。每个元素格式为 {{"slot": 节次编号, "startTime": "HH:MM", "endTime": "HH:MM"}}。如果没有时间信息则输出空数组 []。
7. **缺失信息**用 "" 表示。
8. **输出格式**：必须输出合法 JSON，不要包含任何 Markdown 标记。

【期望的数据结构示例】
{{
  "courses": [
    {{
      "name": "高等数学", "room": "一教201", "teacher": "张三",
      "dayOfWeek": 1, "startSlot": 1, "endSlot": 2, "weeks": [1, 2, 3]
    }}
  ],
  "timeSlots": [
    {{"slot": 1, "startTime": "08:00", "endTime": "08:50"}},
    {{"slot": 2, "startTime": "09:00", "endTime": "09:50"}}
  ]
}}
"""

            step2_response = await kimi_client.chat.completions.create(
                model=KIMI_MODEL,
                messages=[
                    {"role": "user", "content": step2_prompt}
                ],
                extra_body={
                    "thinking": {"type": "disabled"}
                },  # 关闭思考
                stream=True,
            )

            full_text = ""
            async for chunk in step2_response:
                if chunk.choices and chunk.choices[0].delta.content:
                    delta = chunk.choices[0].delta.content
                    full_text += delta
                    yield json.dumps({"status": "generating", "message": delta}, ensure_ascii=False) + "\n"
                    await asyncio.sleep(0.01)

            yield json.dumps({"status": "progress", "message": "分析完毕，正在进行最后的数据封装..."}, ensure_ascii=False) + "\n"
            await asyncio.sleep(0.1)

            # 清理 Markdown 标记并校验 JSON
            cleaned_text = full_text.replace("```json", "").replace("```", "").strip()

            try:
                parsed_json = json.loads(cleaned_text)
                yield json.dumps({"status": "success", "data": parsed_json}, ensure_ascii=False) + "\n"
            except json.JSONDecodeError:
                yield json.dumps({"status": "error", "message": "模型输出的格式出现混乱，JSON 提取失败"}, ensure_ascii=False) + "\n"

        except Exception as e:
            traceback.print_exc()  # 打印完整错误到服务器终端
            yield json.dumps({"status": "error", "message": f"系统内部错误: {str(e)}"}, ensure_ascii=False) + "\n"

    return StreamingResponse(process_stream(), media_type="application/x-ndjson")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
