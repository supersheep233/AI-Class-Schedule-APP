import requests
import time

def test_ime_few_shot(scenario_name, system_prompt, examples, user_input, max_tokens=30):
    print(f"\n▶️ 开始测试场景: {scenario_name}")
    print(f"📥 用户输入: {user_input}")

    url = "http://localhost:11434/api/generate"

    # 【黑魔法：构建 Few-Shot 模板】
    # 不讲大道理，直接给它看真实的输入输出例子
    full_prompt = f"<|im_start|>system\n{system_prompt}<|im_end|>\n"
    for user_ex, assistant_ex in examples:
        full_prompt += f"<|im_start|>user\n{user_ex}<|im_end|>\n"
        full_prompt += f"<|im_start|>assistant\n{assistant_ex}<|im_end|>\n"

    # 拼接当前用户的真实输入
    full_prompt += f"<|im_start|>user\n{user_input}<|im_end|>\n<|im_start|>assistant\n"

    payload = {
        "model": "qwen3.5:0.8b",
        "prompt": full_prompt,
        "stream": False,
        "raw": True,
        "options": {
            "temperature": 0.0,
            "num_predict": max_tokens,
            "top_k": 1,
            "num_gpu": 99 # 【关键提速】强制 Ollama 将所有层卸载到 GPU（如果没有 GPU，Ollama 会自动忽略此参数并在 CPU 上跑）
        }
    }

    start_time = time.time()
    try:
        response = requests.post(url, json=payload, timeout=5)
        response.raise_for_status()

        result = response.json().get("response", "").strip()
        end_time = time.time()

        print(f"⏱️ 耗时: {(end_time - start_time)*1000:.1f} ms")
        print(f"🔤 模型输出: {result}")

    except requests.exceptions.RequestException as e:
        print(f"❌ 请求失败: {e}")
    print("-" * 50)


if __name__ == "__main__":
    print("🚀 启动 [Few-Shot 示例教学] AI 输入法测试...\n")

    # ==========================================
    # 场景 1：拼音与中英混输（给它打个样）
    # ==========================================
    sys_1 = "将拼音转化为精准的中文，保留英文专业词汇。只输出结果。"
    examples_1 = [
        ("jintian wanshang xie Python", "今天晚上写Python"),
        ("zhe ge bug wo zhao le ban tian", "这个bug我找了半天")
    ]
    test_ime_few_shot(
        "拼音与中英混输解析", sys_1, examples_1,
        user_input="wo zai yong CH582 he VEML7700 zuo ce guang yi"
    )

    # ==========================================
    # 场景 2：长句补全（纠正它的语法习惯）
    # ==========================================
    sys_2 = "补全句子，使其符合逻辑。不要重复已有内容。"
    examples_2 = [
        ("这个硬件方案我已经", "评估过了，没有大问题。"),
        ("由于内存泄漏，导致", "程序直接崩溃了。")
    ]
    test_ime_few_shot(
        "开发语境下的长句补全", sys_2, examples_2,
        user_input="关于T113-S3板子上的6麦克风阵列，ALSA的驱动配置我已经"
    )

    # ==========================================
    # 场景 3：口语化重写
    # ==========================================
    sys_3 = "将口语化内容重写为书面规范表达。"
    examples_3 = [
        ("这破电脑太慢了，代码编译卡半天", "当前设备性能瓶颈严重，导致代码编译耗时过长。"),
        ("老板，这需求我干不了", "领导，评估后发现该需求目前在技术实现上存在较大风险。")
    ]
    test_ime_few_shot(
        "口语化表达重写", sys_3, examples_3,
        user_input="这Flutter代码跑起来太卡了，课表app的UI得重写"
    )
