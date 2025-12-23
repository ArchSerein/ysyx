/***************************************************************************************
* Copyright (c) 2014-2022 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "sdb.h"

#define NR_WP 32

static WP wp_pool[NR_WP] = {};
static WP *head = NULL, *free_ = NULL;

void init_wp_pool() {
  int i;
  for (i = 0; i < NR_WP; i ++) {
    wp_pool[i].NO = i;
    wp_pool[i].result = 0;
    wp_pool[i].hit_count = 0;
    strcpy(wp_pool[i].str, "");
    wp_pool[i].enable = false;
    wp_pool[i].next = (i == NR_WP - 1 ? NULL : &wp_pool[i + 1]);
  }

  head = NULL;
  free_ = wp_pool;
}

/* TODO: Implement the functionality of watchpoint */

WP* new_wp(char *e)
{
  bool success = true;
  WP* ret = free_;
  strcpy(ret->str, e);
  ret->result = expr(e, &success);
  ret->enable = true;
  if(success == false) {
    printf("cal fail\n");
  }
  WP* tmp = free_->next;
  free_->next = head;
  head = free_;
  free_ = tmp;
  return ret;
}

int free_wp(int NO)
{
  WP *p = head;
  WP *q = head;
  for(; p != NULL; p = p->next)
  {
    if(p->NO == NO)
      break;
    if(p != head)
      q = q->next;
  }
  if(p == NULL)
    return -1;
  if(p == head)
    head = q->next;
  p->enable = false;
  WP *tmp = free_->next;
  free_->next = p;
  q->next = p->next;
  p->next = tmp;
  return 0;
}

void info_w()
{
  for(WP *p = head; p != NULL; p = p->next)
  {
    printf("%d\t%s\t%d\t%d\t%s\n", p->NO, p->str, p->result, p->hit_count, p->enable ? "true" : "false");
  }
}

int config_watchpoint(void)
{
  bool success = true;
  for(WP *p = head; p != NULL; p = p->next)
  {
    int num = expr(p->str, &success);
    if(p->result != num)
    {
      printf("The value of the expression:%s changed from %d to %d\n", p->str, p->result, num);
      ++p->hit_count;
      return 1;
    }
  }
  return 0;
}

