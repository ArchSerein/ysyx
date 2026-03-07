#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <regex.h>
#include <cassert>
#include "defs.hpp"
#include "debug.hpp"
#include "pmem.hpp"

enum {
  TK_HNUMBER,
  TK_NUMBER,
  TK_U,
  TK_NOTYPE = 256,
  TK_EQ,
  TK_NEQ,
  TK_AND,
  TK_REG,
  TK_MINUS,
  TK_DEREF,
  TK_PLUS = '+',
  TK_SUB = '-',
  TK_MUL = '*',
  TK_DIV = '/',
  TK_LPAREN = '(',
  TK_RPAREN = ')',

  /* TODO: Add more token types */

};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {

  /* TODO: Add more rules.
   * Pay attention to the precedence level of different rules.
   */

  {"0x[0-9a-f]+", TK_HNUMBER},
  {" +", TK_NOTYPE},    // spaces
  {"u+", TK_U},
  {"\\+", '+'},         // plus
  {"==", TK_EQ},        // equal
  {"[0-9]+", TK_NUMBER},
  {"\\-", '-'},
  {"\\*", '*'},
  {"\\/", '/'},
  {"\\(", '('},
  {"\\)", ')'},
  {"!=", TK_NEQ},
  {"&&", TK_AND},
  {"\\$[0-9a-z]+", TK_REG},
};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};

/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i ++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[2048] __attribute__((used)) = {};
static int nr_token __attribute__((used))  = 0;

static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i ++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s",
            i, rules[i].regex, position, substr_len, substr_len, substr_start);

        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        switch (rules[i].token_type) {
          case TK_MUL:
          case TK_PLUS:
          case TK_DIV:
          case TK_EQ:
          case TK_NEQ:
          case TK_AND:
          case TK_LPAREN:
          case TK_RPAREN:
          case TK_SUB:
                    tokens[nr_token].type = rules[i].token_type;
                    nr_token++;
                    break;
          case TK_HNUMBER:
          case TK_REG:
          case TK_NUMBER:
                          tokens[nr_token].type = rules[i].token_type;
                          int len = substr_len > 31 ? 31 : substr_len;
                          strncpy(tokens[nr_token].str, substr_start, len);
                          tokens[nr_token].str[len] = '\0';
                          nr_token++;
                          break;
          /*
          default:
                    break;
          */
        }

        break;
      }
    }

    if (i == NR_REGEX) {
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }

  return true;
}

bool check_parentheses(int p, int q, bool *iseval)
{
  int count = 0;
  int surrounded = 0;
  bool ret = true;
  for(int i = p; i <= q; i++)
  {
    if(tokens[i].type == TK_LPAREN)
    {
      if(i > p && i < q)
        ++surrounded;
      ++count;
    }
    else if(tokens[i].type == TK_RPAREN)
    {
      if(i > p && i < q)
        --surrounded;
      if(surrounded < 0)
        ret = false;
      --count;
    }
  }
  if(count == 0)
    *iseval = true;
  else
    *iseval = false;
  if(tokens[p].type == TK_LPAREN && tokens[q].type == TK_RPAREN && ret)
    return true;
  else {
    return false;
  }
}

int find_op(int p, int q)
{
  int surrounded = 0;
  int op = 0;
  int privity = -1;

  for(; p <= q; q--)
  {
    if(tokens[q].type == TK_LPAREN)
      ++surrounded;
    else if (tokens[q].type == TK_RPAREN) {
      --surrounded;
    }
    else if(surrounded == 0){
      switch (tokens[q].type) {
        case TK_EQ:
        case TK_NEQ:
        case TK_AND:
                  return q;
        case '+':
        case '-':
                  if(privity < 2) {
                    privity = 2;
                    op = q;
                  }
                  break;
        case '*':
        case '/':
                  if(privity < 1) {
                    privity = 1;
                    op = q;
                  }
                  break;
        case TK_MINUS:
        case TK_DEREF:
                  if(privity < 0)
                  {
                    op = q;
                    privity = 0;
                  }
                  break;
        default : break;
      }
    }
  }
  return op;
}

uint32_t eval(int p, int q, bool *success)
{
  bool iseval = true;
  if (p > q)
  {
    return 0;
  }
  else if (p == q) {
    switch (tokens[p].type) {
      case TK_NUMBER: return atoi(tokens[p].str);
      case TK_HNUMBER: return strtol(tokens[p].str, NULL, 16);
      case TK_REG: return isa_reg_str2val(tokens[p].str);
    }
  }
  else if (check_parentheses(p, q, &iseval) == true){
    return eval(p+1, q-1, success);
  }
  else if(iseval == true)
  {
    int op = find_op(p, q);

    uint32_t val1 = eval(p, op-1, success);
    uint32_t val2 = eval(op+1, q, success);

    switch (tokens[op].type) {
      case '+' : return val1 + val2;
      case '-' : return val1 - val2;
      case '*' : return val1 * val2;
      case '/' : if(val2) 
                    return val1 / val2;
                  else
                  {
                    printf("warning: division by zero\n");
                    *success = false;
                    return -1;
                  }
      case TK_EQ:
                  if(val1 == val2)  return 1;
                  else  return 0;
      case TK_NEQ:
                  if(val1 != val2)  return 1;
                  else  return 0;
      case TK_AND: return val1 && val2;
      case TK_DEREF: return vaddr_read((uint32_t)val2, 4);
      case TK_MINUS: return ~val2 + 1;
      default : printf("type mismatch\n");
                *success = false;
                return -1;
    }
  }
  return -1;
}

uint32_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }

  /* TODO: Insert codes to evaluate the expression. */
  for (int i = 0; i < nr_token; i++) {
    if(tokens[i].type == '-' && (i == 0 || tokens[i - 1].type == TK_LPAREN))
      tokens[i].type = TK_MINUS;
    if (tokens[i].type == '*' && (i == 0 || tokens[i - 1].type == TK_LPAREN)) {
      tokens[i].type = TK_DEREF;
    }
  }
  uint32_t result = eval(0, nr_token - 1, success);

  return result;
}
