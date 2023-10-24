---
layout: post
author: '孔家东苑'
title: "Tinyget 人工智能助手开发记录"
draft: true

album: "Tinyget 开发记录"

license: "cc-by-nc-nd-4.0"
permalink: /tinyget-ai-helper/
description: " 探讨在 Tinyget 开发过程中引入大型语言模型的相关技术 "
category:
  - Linux
tags:
  - 包管理器
---

## 背景

在编写 TinyGet 项目的主体部分时，我大部分的时间都在做这样的事情：

1. 将包管理器的功能抽象成接口；
2. 将接口实现为包管理器的命令；

在实现的过程中，难免遇到某一个功能在某一个平台上并不能按照我们的预期运行，而且用户的错误指令同样会在底层带来各式各样的异常。因此我常常在想，是否可以使用现在风头正盛的大语言模型进行辅助，在出错时为用户指出错误，并给出相应的解决方案呢？

很快我就着手实现这个想法，经过广泛的调研，我实现了一个针对包管理器的人工智能助手，取得了令人惊讶的效果。

尽管在当前的技术环境下，已经有许多基于 OpenAI 接口开发的工具，但亲自开发一个工具仍然能带来深刻的理解和学习。

## 技术选型

提到大语言模型，OpenAI 应该是第一选择。但是在最初的设想中，我希望这个 AI 助手可以离线运行，因此我在最开始对 OpenAI 以外的开源大模型进行了调研，其中最值得注意的就是 LLaMA 大羊驼模型。

[Llama 2 - Meta AI][001]

有优秀的研究者为它进行了量化裁剪，并使用 C++语言开发了可以运行于大多数平台的精简版本 llama.cpp：

[ggerganov/llama.cpp: Port of Facebook's LLaMA model in C/C++ (github.com)][002]

但是在当下的算力水平下，llama.cpp 的推理速度仍然堪忧，即便是只有 7B 规模的模型，在 M2 Macbook Pro 下，推理速度也不超过 20 token/s。而且考虑到使用 linux 的很多终端都算力较弱，因此最终舍弃了此方案，仍采用 OpenAI 的在线模型。

## 接口简介

OpenAI 的接口众多，我们主要使用的有两个：

1. 模型查询；
2. 模型使用（就是平常使用的 ChatGPT 的后端）。

模型查询的接口格式如下：

```python
def list_models(self) -> bool:
    """
    Retrieves a list of models from the server.

    :return: A boolean value indicating the success of the request.
    """
    headers = {
        "Authorization": f"Bearer {self.api_key}",
    }
    url = urljoin(self.host, "v1/models")
    response = requests.get(headers=headers, url=url)
    res = json.loads(response.content.decode())["data"]
    return res
```

返回的格式如：

```json
[{
    “created”: 1649358449,
    “id”: “babbage”,
    “object”: “model”,
    “owned_by”: “openai”,
    “parent”: null,
    “permission”: [
        {
            “allow_create_engine”: false,
            “allow_fine_tuning”: false,
            “allow_logprobs”: true,
            “allow_sampling”: true,
            “allow_search_indices”: false,
            “allow_view”: true,
            “created”: 1669085501,
            “group”: null,
            “id”: “modelperm-49FUp5v084tBB49tC4z8LPH5”,
            “is_blocking”: false,
            “object”: “model_permission”,
            “organization”: “*”
        }
    ],
    “root”: “babbage”
},]
```

生成的 API 如下：

```python
def ask(self, query: str) -> str:
    """
    Executes a question by generating a completion based on the provided query.

    Args:
        query (str): The question or query to be asked.

    Returns:
        str: The generated completion as the answer to the question.

    Raises:
        Exception: If no model name is specified before asking a question.
    """
    if self.model is None:
        raise Exception("Please specify a model name before asking a question.")
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": query},
    ]
    result = do_completion(
        host=self.host,
        model=self.model,
        api_key=self.api_key,
        temperature=0.0,
        max_tokens=self.max_tokens,
        messages=messages,
    )
    answer = result["choices"][0]["message"]["content"]
    return answer
```

## 异常处理

这里主要处理三种异常：

```python
class ModelException(Exception):
    def __init__(self, message, model, response):
        """
        Initializes a new instance of the MyClass class.

        Args:
            message (str): The message to be passed to the superclass constructor.
            model: The model to be assigned to the `model` attribute.
            response: The response to be assigned to the `response` attribute.
        """
        super().__init__(message)
        self.model = model
        self.reponse = response

class AIHelperHostError(Exception):
    def __init__(self, message, host):
        """
        Initializes a new instance of the class.

        Args:
            message (str): The message for the exception.
            host (str): The host information.

        Returns:
            None
        """
        super().__init__(message)
        self.host = host

class AIHelperKeyError(Exception):
    def __init__(self, message, host, key, response):
        """
        Initializes a new instance of the class.

        Args:
            message (str): The message to display.
            host (str): The host to connect to.
            key (str): The key to use for authentication.
            response (str): The response to expect.

        Returns:
            None
        """
        super().__init__(message)
        self.host = host
        self.key = key
        self.response = response
```

这三种异常分别对应于：模型无效、url 错误、key 错误，防止底层崩溃影响上层应用。

## Prompt 编写

使用 LLM 很像与人交流，需要明确表达需求后，再约定需要 LLM 为我们做什么。经过不断实验，我完成了这样一份 Prompt，工作良好。

> 你是一个熟练的 Linux 专家，精通各类发行版中的包管理器，也能熟练运用各类软件包管理器的命令。
> 用户将会告诉你他执行的命令、命令的 stdout、命令的 stderr。
> 你帮助用户对当前错误进行解释，并给出建议使用的命令。注意，建议使用的命令应该严格遵循 markdown 语法。

例如，当我故意错误输入 vim 的包名时，会得到如下的信息：

```
tinyget install vimm
```

> 根据 stderr 的提示，你需要以 root 用户身份运行该命令。可以使用 `sudo` 命令来提升权限，例如：
>
> ```bash
> sudo apt install -y vim
> ```
>
> 另外，stderr 中还有一条警告信息，提示 `apt` 命令的 CLI 接口不稳定，需要谨慎使用。如果你需要在脚本中使用 `apt` 命令，可以考虑使用 `apt-get` 命令，它的 CLI 接口更加稳定。

## 参考资料

- [llama][001]
- [ggerganov/llama.cpp][002]

[001]: https://ai.meta.com/llama/
[002]: https://github.com/ggerganov/llama.cpp
